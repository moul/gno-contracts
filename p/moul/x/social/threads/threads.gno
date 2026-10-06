// Package threads is the engine behind an embeddable discussion block: the
// text half of what a reaction bar does, keyed on the PAGE it is shown under
// rather than on the realm that stores it.
//
// # Why not a forum
//
// A forum is a destination, and a destination has to earn its traffic before
// anybody writes the first post. A block does not: it is dropped into pages
// that already have readers, and the discussion attaches to the object it is
// about. One realm holds every thread, every host realm ships the same two
// lines, and no host realm stores anything.
//
// That is the shape the web settled on for comments in 2010, and the same one
// [gno.land/p/moul/reactions] uses for the tally. This package is deliberately
// its neighbour: reactions are a closed palette and need no moderation, text
// needs some, and the two are separate so a realm can take the cheap one alone.
//
// # The model
//
//	Board    every thread, across every page
//	Thread   a root post: page, author, body, height, pin, replies
//	Reply    an author, a body and a height, and nothing else
//
// A thread remembers the set of addresses that have replied to it, which is
// what lets a realm implement "earned by being replied to" without counting
// one person twice. [Board.Reply] reports whether the replier was new, so the
// mint rule has exactly one signal and exactly one call site.
//
// # Ordering, and the pin
//
// [Board.List] returns pinned threads first, then the rest, both newest first,
// which is a partition and not a sort: no comparator, no tie to break, and the
// same input always produces the same page. A pin is an absolute height, so it
// expires on its own and nothing has to be swept.
//
// The realm decides what a pin costs. This package only enforces that a pin
// cannot be moved backwards, so buying one does not shorten somebody else's.
//
// # Page keys and bodies
//
// A page key is a package path, the full one, chain domain included.
// [ValidPage] bounds it to a path-shaped lowercase ASCII string of at most
// [MaxPageLen] bytes, so a stored key can never be a markdown payload. A body
// is bounded by [MaxBodyLen] and rejected when it carries a control character,
// but it is otherwise free text and therefore attacker-controlled markdown:
// everything here escapes it with ui.Inline or ui.Cell, and so must any realm
// that renders one itself.
package threads

import (
	"errors"
	"strconv"
	"strings"

	"gno.land/p/moul/kit/store/v0"
	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/md/v0"
)

const (
	// MaxPageLen is the longest page key accepted, matching
	// gno.land/p/moul/reactions so the two blocks agree on what a page is.
	MaxPageLen = 120

	// MaxBodyLen is the longest post or reply accepted, in bytes. Long
	// enough for a real comment, short enough that one call cannot lock an
	// unbounded storage deposit somebody else is paying for.
	MaxBodyLen = 1000

	// ExcerptLen is how much of a body a listing shows.
	ExcerptLen = 60
)

// The errors a caller can get back. A p/ returns them; the realm decides to
// abort.
var (
	ErrBadPage   = errors.New("threads: not a page key")
	ErrBadBody   = errors.New("threads: body is empty, too long, or has control characters")
	ErrNoThread  = errors.New("threads: no such thread")
	ErrPinIsPast = errors.New("threads: a pin cannot be moved backwards")
)

// Reply is one answer under a thread.
type Reply struct {
	Author address
	Body   string
	At     int64 // block height
}

// Thread is a root post and everything under it.
type Thread struct {
	Page    string
	Author  address
	Body    string
	At      int64 // block height
	Replies []Reply

	// PinnedUntil is the height the thread stops being pinned at. Zero is
	// never pinned, and a past height is an expired pin: nothing has to
	// sweep it.
	PinnedUntil int64

	// repliers is the set of addresses that have replied, so a thread can
	// be scored on people rather than on messages.
	repliers map[string]bool
}

// Pinned reports whether the thread is pinned at height now.
func (t *Thread) Pinned(now int64) bool { return t != nil && t.PinnedUntil > now }

// Repliers is how many distinct addresses have replied.
func (t *Thread) Repliers() int {
	if t == nil {
		return 0
	}
	return len(t.repliers)
}

// HasReplied reports whether who has already replied to this thread.
func (t *Thread) HasReplied(who address) bool {
	if t == nil {
		return false
	}
	return t.repliers[who.String()]
}

// Board holds every thread, indexed by the page it was posted under.
type Board struct {
	threads *store.Store
	pages   map[string][]store.ID // page key -> ids, oldest first
}

// NewBoard returns an empty board.
func NewBoard() *Board {
	return &Board{threads: store.Named("thread"), pages: map[string][]store.ID{}}
}

// Post opens a thread on page and returns its id.
func (b *Board) Post(page string, author address, body string, at int64) (store.ID, error) {
	if !ValidPage(page) {
		return 0, ErrBadPage
	}
	if !ValidBody(body) {
		return 0, ErrBadBody
	}
	id := b.threads.Add(&Thread{
		Page:     page,
		Author:   author,
		Body:     body,
		At:       at,
		repliers: map[string]bool{},
	})
	b.pages[page] = append(b.pages[page], id)
	return id, nil
}

// Reply appends to a thread and reports whether this author had never replied
// to it before.
//
// That boolean is the mint signal: a realm that pays an author for attention
// wants distinct people, not distinct messages, and a thread's own author
// replying to themselves is never new.
func (b *Board) Reply(id store.ID, author address, body string, at int64) (isNewReplier bool, err error) {
	t, ok := b.Get(id)
	if !ok {
		return false, ErrNoThread
	}
	if !ValidBody(body) {
		return false, ErrBadBody
	}
	t.Replies = append(t.Replies, Reply{Author: author, Body: body, At: at})

	key := author.String()
	if author == t.Author || t.repliers[key] {
		return false, nil
	}
	t.repliers[key] = true
	return true, nil
}

// Pin keeps a thread at the top of its page until height until.
//
// It refuses to move a pin backwards, so a cheap pin cannot cut short an
// expensive one, and extends from whichever is later: the current pin or now.
func (b *Board) Pin(id store.ID, until int64) error {
	t, ok := b.Get(id)
	if !ok {
		return ErrNoThread
	}
	if until <= t.PinnedUntil {
		return ErrPinIsPast
	}
	t.PinnedUntil = until
	return nil
}

// Get returns a thread by id.
func (b *Board) Get(id store.ID) (*Thread, bool) {
	v, ok := b.threads.Get(id)
	if !ok {
		return nil, false
	}
	return v.(*Thread), true
}

// Len is how many threads exist, across every page.
func (b *Board) Len() int { return b.threads.Len() }

// Pages is how many pages have ever been posted on.
func (b *Board) Pages() int { return len(b.pages) }

// PageLen is how many threads a page holds.
func (b *Board) PageLen(page string) int { return len(b.pages[page]) }

// Listing is one row of [Board.List]: the thread and the id a link needs.
type Listing struct {
	ID     store.ID
	Thread *Thread
}

// List returns up to limit threads on page: pinned first, then the rest, both
// newest first.
//
// It is a partition and not a sort. There is no comparator and no tie to
// break, so two identical calls always produce the same page, which is what a
// Render needs. limit <= 0 returns everything.
func (b *Board) List(page string, now int64, limit int) []Listing {
	ids := b.pages[page]
	var pinned, rest []Listing
	for i := len(ids) - 1; i >= 0; i-- {
		t, ok := b.Get(ids[i])
		if !ok {
			continue
		}
		item := Listing{ID: ids[i], Thread: t}
		if t.Pinned(now) {
			pinned = append(pinned, item)
		} else {
			rest = append(rest, item)
		}
	}
	out := append(pinned, rest...)
	if limit > 0 && len(out) > limit {
		out = out[:limit]
	}
	return out
}

// Recent returns up to limit threads from every page, newest first. It is what
// the hosting realm's own homepage shows.
func (b *Board) Recent(limit int) []Listing {
	var out []Listing
	for _, e := range b.threads.PageReverse(1, limit) {
		out = append(out, Listing{ID: e.ID, Thread: e.Value.(*Thread)})
	}
	return out
}

// ValidPage reports whether page is a usable page key: path-shaped, lowercase
// ASCII, no leading, trailing or doubled slash, at most [MaxPageLen] bytes.
//
// Same rule as gno.land/p/moul/reactions, deliberately: a realm embedding both
// blocks passes one key to both.
func ValidPage(page string) bool {
	if page == "" || len(page) > MaxPageLen {
		return false
	}
	if strings.HasPrefix(page, "/") || strings.HasSuffix(page, "/") ||
		strings.Contains(page, "//") || !strings.Contains(page, "/") {
		return false
	}
	for i := 0; i < len(page); i++ {
		c := page[i]
		switch {
		case c >= 'a' && c <= 'z', c >= '0' && c <= '9':
		case c == '/' || c == '.' || c == '-' || c == '_' || c == ':':
		default:
			return false
		}
	}
	return true
}

// ValidBody reports whether body can be stored: non-empty after trimming,
// within [MaxBodyLen], and free of control characters.
//
// Control characters are refused rather than stripped because a body is shown
// back to its author: silently rewriting what somebody wrote is worse than
// telling them it was refused. Everything else is allowed and escaped at
// render time, since a validator and an escaper protect against different
// mistakes.
func ValidBody(body string) bool {
	if len(body) > MaxBodyLen || strings.TrimSpace(body) == "" {
		return false
	}
	for i := 0; i < len(body); i++ {
		c := body[i]
		if c < 0x20 && c != '\n' && c != '\t' || c == 0x7f {
			return false
		}
	}
	return true
}

// Block renders the embeddable widget: the page's threads, then the button
// that opens a new one.
//
// realmPath is the realm that owns Post and Reply, given as the full package
// path from its gnomod.toml module line. It is a parameter and not a constant
// because this package is the engine and not the deployment.
func Block(realmPath, page string, items []Listing, total int, now int64) string {
	out := ""
	if len(items) == 0 {
		out += ui.Empty("No discussion yet.")
	} else {
		t := ui.NewTable("", "#", "thread", "by", "replies")
		for _, it := range items {
			mark := ""
			if it.Thread.Pinned(now) {
				mark = "📌"
			}
			t.Row(
				mark,
				// The link title is the id and never the body. md.Link
				// escapes markdown but NOT a pipe (sanitize.InlineText
				// leaves it; only ui.Cell rewrites it), so a body used as
				// a link title inside a table opens a column.
				md.Link("#"+it.ID.String(), ThreadURL(realmPath, it.ID)),
				// Cut first, escape second: the other order can strand a
				// trailing backslash that escapes the chrome after it.
				ui.Cell(ui.ShortN(it.Thread.Body, ExcerptLen, 0)),
				ui.Addr(it.Thread.Author),
				strconv.Itoa(len(it.Thread.Replies)),
			)
		}
		out += t.String()
	}

	out += "\n" + ui.ActionIn(realmPath, "💬 Post", "Post", "page", page, "body", "")
	if total > len(items) {
		out += " · " + md.Link(
			strconv.Itoa(total)+" threads",
			PageURL(realmPath, page),
		)
	}
	return out + "\n"
}

// ThreadURL is the gnoweb path of one thread on the hosting realm.
func ThreadURL(realmPath string, id store.ID) string {
	return RealmURL(realmPath) + ":thread/" + id.String()
}

// PageURL is the gnoweb path of a page's full thread list.
func PageURL(realmPath, page string) string {
	return RealmURL(realmPath) + ":page/" + page
}

// RealmURL is the gnoweb path of a realm given as a package path.
//
// The chain domain is the first element of a package path and a gnoweb path is
// the rest of it, so this is a prefix strip and not a hostname this package
// has to know.
func RealmURL(realmPath string) string {
	if i := strings.Index(realmPath, "/"); i >= 0 {
		return realmPath[i:]
	}
	return "/" + realmPath
}
