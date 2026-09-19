package wiki

import (
	"errors"
	"time"

	"gno.land/p/moul/fifo/v0"
	"gno.land/p/moul/ulist/v0"
	"gno.land/p/nt/avl/v0"
)

// Defaults for New. Retention is the number of most-recent revisions per page
// whose body stays on chain; MaxBody caps a single revision.
const (
	DefaultRetention = 3
	DefaultMaxBody   = 32 << 10 // 32 KiB
	DefaultRecent    = 50
	MaxSummaryLen    = 200
)

var (
	ErrNoSuchPage     = errors.New("wiki: no such page")
	ErrPageExists     = errors.New("wiki: page already exists")
	ErrBodyTooLarge   = errors.New("wiki: body exceeds the size limit")
	ErrEmptyBody      = errors.New("wiki: empty body")
	ErrNoChange       = errors.New("wiki: body is identical to the current revision")
	ErrSummaryTooLong = errors.New("wiki: edit summary too long")
	ErrBadProtection  = errors.New("wiki: unknown protection level")
	ErrNoSuchRevision = errors.New("wiki: no such revision")
	ErrBodyEvicted    = errors.New("wiki: that revision's body is no longer held on chain")
	ErrSpecial        = errors.New("wiki: the Special namespace is generated, not stored")
)

// Wiki is the whole encyclopedia: pages, the indexes derived from them, and
// the recent-changes feed.
//
// Every mutating method takes author, now and height from the caller instead
// of reading them from the chain, so the engine has no chain imports and the
// tests drive time and height explicitly.
type Wiki struct {
	pages     *avl.Tree // Title.Key() -> *Page
	backlinks *avl.Tree // target Title.Key() -> *avl.Tree (source key -> Title)
	cats      *avl.Tree // category Title.Key() -> *avl.Tree (member key -> Title)
	talk      *avl.Tree // Title.Key() -> *ulist.List of *Comment (see talk.gno)
	recent    *fifo.List

	nextRev     uint64
	nextComment uint64
	retention int
	maxBody   int

	numPages    int // pages with at least one revision and not blanked
	numRevs     int
	numComments int
	bytesHeld   int // retained body and comment bytes, the realm's visible rent
}

// New returns an empty wiki. A retention or maxBody below 1 falls back to the
// package default.
func New(retention, maxBody int) *Wiki {
	if retention < 1 {
		retention = DefaultRetention
	}
	if maxBody < 1 {
		maxBody = DefaultMaxBody
	}
	return &Wiki{
		pages:     avl.NewTree(),
		backlinks: avl.NewTree(),
		cats:      avl.NewTree(),
		talk:      avl.NewTree(),
		recent:    fifo.New(DefaultRecent),
		retention: retention,
		maxBody:   maxBody,
	}
}

// Stats is a snapshot of the wiki's size and of what it is paying for.
type Stats struct {
	Pages     int
	Revisions int
	Comments  int
	BytesHeld int // bytes of article text and comments currently on chain
	Retention int
}

// Stats returns the current counters.
func (w *Wiki) Stats() Stats {
	return Stats{
		Pages:     w.numPages,
		Revisions: w.numRevs,
		Comments:  w.numComments,
		BytesHeld: w.bytesHeld,
		Retention: w.retention,
	}
}

// Page returns the page stored at raw, without following redirects.
func (w *Wiki) Page(raw string) (*Page, error) {
	t, err := ParseTitle(raw)
	if err != nil {
		return nil, err
	}
	return w.PageByTitle(t)
}

// PageByTitle is Page for an already-parsed title.
func (w *Wiki) PageByTitle(t Title) (*Page, error) {
	v := w.pages.Get(t.Key())
	if v == nil {
		return nil, ErrNoSuchPage
	}
	return v.(*Page), nil
}

// Exists reports whether a title has a page. A blanked page still exists: its
// history is the point of the wiki.
func (w *Wiki) Exists(t Title) bool { return w.pages.Has(t.Key()) }

// Resolve follows at most one redirect hop and returns the destination page
// along with the page that was asked for. MediaWiki also stops at one hop:
// chains are a vandalism vector and a loop is unrenderable.
func (w *Wiki) Resolve(raw string) (dest, asked *Page, err error) {
	p, err := w.Page(raw)
	if err != nil {
		return nil, nil, err
	}
	if p.redirect == "" {
		return p, p, nil
	}
	target, err := w.Page(p.redirect)
	if err != nil {
		return p, p, nil // dangling redirect: render the stub itself
	}
	return target, p, nil
}

// Edit writes a new revision. It does not check authority: the caller decides
// who may write, using Page.Protection and whatever roster it keeps. Passing a
// body byte-identical to the current one is an error, so a no-op edit cannot
// be used to spam the history or the recent-changes feed.
func (w *Wiki) Edit(author address, now time.Time, height int64, raw, body, summary string, minor bool) (*Revision, error) {
	t, err := ParseTitle(raw)
	if err != nil {
		return nil, err
	}
	if t.NS == NSSpecial {
		return nil, ErrSpecial
	}
	if body == "" {
		return nil, ErrEmptyBody
	}
	if len(body) > w.maxBody {
		return nil, ErrBodyTooLarge
	}
	if len(summary) > MaxSummaryLen {
		return nil, ErrSummaryTooLong
	}

	p, _ := w.PageByTitle(t)
	kind := KindEdit
	if p == nil {
		kind = KindCreate
	} else if p.head != nil && p.head.Hash == hashBody(body) {
		return nil, ErrNoChange
	}
	return w.commit(p, t, author, now, height, body, summary, kind, minor), nil
}

// Revert restores the body of an earlier revision as a new revision, the way
// a wiki undo works: the vandalized revision stays in the history, it is just
// no longer current. It fails if that revision's body has aged out of the
// retention window, which is the honest failure mode of a bounded history.
func (w *Wiki) Revert(author address, now time.Time, height int64, raw string, revID uint64, summary string) (*Revision, error) {
	p, err := w.Page(raw)
	if err != nil {
		return nil, err
	}
	old := p.Revision(revID)
	if old == nil {
		return nil, ErrNoSuchRevision
	}
	body, ok := old.Body()
	if !ok {
		return nil, ErrBodyEvicted
	}
	if p.head != nil && p.head.Hash == old.Hash {
		return nil, ErrNoChange
	}
	if len(summary) > MaxSummaryLen {
		return nil, ErrSummaryTooLong
	}
	return w.commit(p, p.Title, author, now, height, body, summary, KindRevert, false), nil
}

// Blank replaces a page's content with a tombstone revision. It is the
// deletion a chain can honestly offer: the page stops rendering and stops
// costing rent as its bodies age out, while the revision spine stays as proof
// that something was there and who removed it. Use Purge to release the
// retained bytes immediately.
func (w *Wiki) Blank(author address, now time.Time, height int64, raw, reason string) (*Revision, error) {
	p, err := w.Page(raw)
	if err != nil {
		return nil, err
	}
	if len(reason) > MaxSummaryLen {
		return nil, ErrSummaryTooLong
	}
	rev := w.commit(p, p.Title, author, now, height, "", reason, KindBlank, false)
	if !p.Blanked {
		p.Blanked = true
		w.numPages--
	}
	return rev, nil
}

// Purge evicts every retained body of a page immediately and returns the
// number of bytes released. The spine, including each body's hash, is
// untouched. This is the lever for content that must stop being served from
// realm state; it cannot and does not remove the transactions that wrote it.
func (w *Wiki) Purge(raw string) (int, error) {
	p, err := w.Page(raw)
	if err != nil {
		return 0, err
	}
	released := 0
	p.revs.Iterator(0, p.revs.Size()-1, func(_ int, v any) bool {
		released += v.(*Revision).evict()
		return false
	})
	w.bytesHeld -= released
	return released, nil
}

// Move renames a page, keeping its history, and leaves a redirect behind at
// the old title so existing links keep resolving.
func (w *Wiki) Move(author address, now time.Time, height int64, from, to, summary string) error {
	src, err := w.Page(from)
	if err != nil {
		return err
	}
	dst, err := ParseTitle(to)
	if err != nil {
		return err
	}
	if dst.NS == NSSpecial {
		return ErrSpecial
	}
	if w.Exists(dst) {
		return ErrPageExists
	}

	old := src.Title
	w.unindex(src)
	w.pages.Remove(old.Key())
	src.Title = dst
	w.pages.Set(dst.Key(), src)
	w.index(src)

	w.pushRecent(src.Title, w.metaRevision(src, author, now, height, "moved from "+old.String(), KindMove))

	stub := "#REDIRECT [[" + dst.String() + "]]\n"
	w.commit(nil, old, author, now, height, stub, "moved to "+dst.String(), KindMove, false)
	return nil
}

// SetProtection changes a page's edit gate.
func (w *Wiki) SetProtection(author address, now time.Time, height int64, raw, level string) error {
	p, err := w.Page(raw)
	if err != nil {
		return err
	}
	lvl, err := ParseProtection(level)
	if err != nil {
		return err
	}
	p.Protection = lvl
	w.pushRecent(p.Title, w.metaRevision(p, author, now, height, "protection: "+lvl.String(), KindProtect))
	return nil
}

// metaRevision records an event that changed a page without changing its text
// (a move, a protection change). It carries no body of its own and inherits
// the current revision's hash and size, so the history reads as "this is still
// the same text" instead of "the article was blanked".
func (w *Wiki) metaRevision(p *Page, author address, now time.Time, height int64, summary string, kind Kind) *Revision {
	rev := w.newRevision(p, author, now, height, "", summary, kind, true)
	rev.kept = false
	if p.head != nil {
		rev.Hash = p.head.Hash
		rev.Size = p.head.Size
	}
	return rev
}

// commit appends a revision, re-derives the page's indexes from the new body
// and enforces the retention window. p may be nil, in which case the page is
// created at t.
func (w *Wiki) commit(p *Page, t Title, author address, now time.Time, height int64, body, summary string, kind Kind, minor bool) *Revision {
	if p == nil {
		p = &Page{Title: t, Created: now, revs: ulist.New()}
		w.pages.Set(t.Key(), p)
		w.numPages++
	} else {
		w.unindex(p)
		if p.Blanked && body != "" {
			p.Blanked = false
			w.numPages++
		}
	}

	rev := w.newRevision(p, author, now, height, body, summary, kind, minor)
	p.head = rev
	w.reindex(p, body)
	w.enforceRetention(p)
	w.pushRecent(p.Title, rev)
	return rev
}

// newRevision allocates the next revision, appends it and accounts its bytes.
func (w *Wiki) newRevision(p *Page, author address, now time.Time, height int64, body, summary string, kind Kind, minor bool) *Revision {
	w.nextRev++
	prev := uint64(0)
	if n := p.revs.Size(); n > 0 {
		prev = p.revs.MustGet(n - 1).(*Revision).ID
	}
	rev := &Revision{
		ID:      w.nextRev,
		Prev:    prev,
		Kind:    kind,
		Author:  author,
		Time:    now,
		Height:  height,
		Summary: summary,
		Hash:    hashBody(body),
		Size:    len(body),
		Minor:   minor,
		body:    body,
		kept:    true,
	}
	p.revs.Append(rev)
	w.numRevs++
	w.bytesHeld += len(body)
	return rev
}

// enforceRetention evicts the body that just fell out of the window.
//
// It counts only revisions that still hold a body, so bodyless move and
// protection entries do not push real text out of the window early. One
// eviction per commit is enough because the window only ever moves by one, and
// the backward walk is bounded by scanLimit so a page with a long run of meta
// revisions cannot make a single edit O(history).
func (w *Wiki) enforceRetention(p *Page) {
	const scanLimit = 64
	kept, scanned := 0, 0
	p.revs.Iterator(p.revs.Size()-1, 0, func(_ int, v any) bool {
		scanned++
		r := v.(*Revision)
		if !r.kept {
			return scanned >= scanLimit
		}
		kept++
		if kept > w.retention {
			w.bytesHeld -= r.evict()
			return true
		}
		return scanned >= scanLimit
	})
}

func (w *Wiki) pushRecent(t Title, r *Revision) {
	w.recent.Prepend(&Change{Title: t, Rev: r})
}

// Recent returns up to n changes, newest first.
func (w *Wiki) Recent(n int) []*Change {
	out := []*Change{}
	for _, e := range w.recent.Entries() {
		if len(out) >= n {
			break
		}
		out = append(out, e.(*Change))
	}
	return out
}

// reindex derives the page's redirect target, outgoing links and categories
// from body, and writes them into the wiki-wide indexes.
func (w *Wiki) reindex(p *Page, body string) {
	p.redirect = redirectTarget(body)
	p.links = nil
	p.cats = nil

	for _, raw := range ScanLinks(body, "[[", "]]") {
		t, err := ParseTitle(raw.Target)
		if err != nil || t == p.Title {
			continue
		}
		if t.NS == NSCategory && !raw.Explicit {
			p.cats = appendUnique(p.cats, t.Key())
			continue
		}
		p.links = appendUnique(p.links, t.Key())
	}
	w.index(p)
}

// index adds the page to every index its current content implies.
func (w *Wiki) index(p *Page) {
	for _, key := range p.links {
		addTo(w.backlinks, key, p)
	}
	for _, key := range p.cats {
		addTo(w.cats, key, p)
	}
}

// unindex removes the page from every index, so the next reindex starts clean.
func (w *Wiki) unindex(p *Page) {
	for _, key := range p.links {
		removeFrom(w.backlinks, key, p.Title.Key())
	}
	for _, key := range p.cats {
		removeFrom(w.cats, key, p.Title.Key())
	}
}

func addTo(idx *avl.Tree, key string, p *Page) {
	v := idx.Get(key)
	var set *avl.Tree
	if v == nil {
		set = avl.NewTree()
		idx.Set(key, set)
	} else {
		set = v.(*avl.Tree)
	}
	set.Set(p.Title.Key(), p.Title)
}

func removeFrom(idx *avl.Tree, key, member string) {
	v := idx.Get(key)
	if v == nil {
		return
	}
	set := v.(*avl.Tree)
	set.Remove(member)
	if set.Size() == 0 {
		idx.Remove(key)
	}
}

func members(idx *avl.Tree, key string) []Title {
	out := []Title{}
	v := idx.Get(key)
	if v == nil {
		return out
	}
	v.(*avl.Tree).Iterate("", "", func(_ string, val any) bool {
		out = append(out, val.(Title))
		return false
	})
	return out
}

// Backlinks returns the titles whose current revision links to t, in key
// order. Redlinks are indexed too, so a page created later immediately knows
// who was already pointing at it.
func (w *Wiki) Backlinks(t Title) []Title { return members(w.backlinks, t.Key()) }

// CategoryMembers returns the pages that declare [[Category:name]].
func (w *Wiki) CategoryMembers(t Title) []Title { return members(w.cats, t.Key()) }

// Categories returns every category that has at least one member.
func (w *Wiki) Categories() []Title {
	out := []Title{}
	w.cats.Iterate("", "", func(key string, _ any) bool {
		out = append(out, Title{NS: NSCategory, Name: key[len(NSCategory.Prefix()):]})
		return false
	})
	return out
}

// Titles returns up to count page titles in key order, skipping offset of
// them. An empty ns prefix walks every namespace.
func (w *Wiki) Titles(prefix string, offset, count int) []Title {
	out := []Title{}
	skipped := 0
	w.pages.Iterate(prefix, "", func(key string, v any) bool {
		if prefix != "" && !hasPrefix(key, prefix) {
			return true
		}
		if skipped < offset {
			skipped++
			return false
		}
		out = append(out, v.(*Page).Title)
		return len(out) >= count
	})
	return out
}

func hasPrefix(s, p string) bool { return len(s) >= len(p) && s[:len(p)] == p }

func appendUnique(list []string, v string) []string {
	for _, e := range list {
		if e == v {
			return list
		}
	}
	return append(list, v)
}
