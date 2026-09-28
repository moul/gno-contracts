// Package reactions is the engine behind an embeddable reaction block: the
// one-click "👍 3 · 🔥 1" strip a realm drops into its own Render, keyed on
// the PAGE it is showing rather than on the realm that stores it.
//
// That indirection is the whole idea, and it is the one the web already
// settled on: a single hosted widget, embedded verbatim everywhere, deciding
// what to show from the page identifier it is handed. One realm holds every
// tally, every host realm ships the same two lines, and no host realm stores
// anything.
//
// # The model
//
// A [Board] maps a page key to a [Page]. A page holds three things and
// deliberately nothing else:
//
//   - a count per palette key,
//   - the CURRENT reaction of each address, so a tally counts addresses and
//     not clicks, and so a reader can change their mind,
//   - the last reaction: which key, from whom, at what height.
//
// There is no text anywhere, which is the point. Text needs moderation;
// a closed palette of six emoji does not.
//
// # Keys are names, not glyphs
//
// A reaction is stored and addressed as an ASCII name ("up", "fire"), and the
// glyph is presentation. A name survives a URL query parameter, an avl key and
// a markdown escaper without a single encoding question, and the palette can
// gain a glyph without rewriting stored state.
//
// # Page keys
//
// A page key is a package path (the full one, chain domain included, as
// unsafe.CurrentRealm().PkgPath() reports it). [ValidPage] is what bounds this
// package's exposure: a key is path-shaped, ASCII, and at most [MaxPageLen]
// bytes, so a stored key can never be a markdown payload, a bidi run or an
// unbounded blob. This package only ever puts it in a URL; a realm that shows
// the key as text escapes it there, because a validator and an escaper protect
// against different mistakes.
package reactions

import (
	"strconv"
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/nt/avl/v0"
)

// MaxPageLen is the longest page key accepted. Comfortably past the longest
// real package path (the deepest in moul/gno-contracts is 34 bytes) and short
// enough that a key can never be a payload.
const MaxPageLen = 120

// Board is a set of pages, each with its own tally. The zero value is not
// usable; call [NewBoard].
type Board struct {
	pages *avl.Tree // page key -> *Page
}

// NewBoard returns an empty board.
func NewBoard() *Board { return &Board{pages: avl.NewTree()} }

// Page is one page's tally.
//
// Every read method is nil-safe and answers as if the page were empty, so a
// caller can hand [Board.Page]'s result straight to [Block] without checking.
type Page struct {
	counts  *avl.Tree // palette key -> int
	by      *avl.Tree // address string -> palette key
	lastKey string
	lastWho address
	lastAt  int64
}

// React records who's reaction on page, replacing whatever they had there
// before. It reports whether anything was stored: false means the page key or
// the palette key was rejected, and nothing changed.
//
// height is passed in rather than read from the chain, so this package stays
// testable without a realm and so the caller decides what "when" means.
func (b *Board) React(page string, who address, key string, height int64) bool {
	if !ValidPage(page) || !Valid(key) {
		return false
	}
	p := b.page(page)

	// Replacing a reaction decrements the old bucket first. Without this a
	// reader who clicks twice counts twice, and the tally stops meaning
	// "how many addresses", which is the only thing it is allowed to mean.
	if prev := p.Of(who); prev != "" {
		if prev == key {
			// Same key again: still record it as the last reaction, since the
			// click happened, but leave the counts alone.
			p.lastKey, p.lastWho, p.lastAt = key, who, height
			return true
		}
		p.add(prev, -1)
	}
	p.by.Set(who.String(), key)
	p.add(key, 1)
	p.lastKey, p.lastWho, p.lastAt = key, who, height
	return true
}

// Unreact removes who's reaction from page. It reports whether there was one.
//
// The last-reaction line is deliberately NOT rewound: it records an event that
// happened, and recomputing it would mean walking every address on the page.
// A page whose only reaction is removed goes back to reading as empty, because
// [Page.Total] is what decides that.
func (b *Board) Unreact(page string, who address) bool {
	p := b.Page(page)
	if p == nil {
		return false
	}
	prev := p.Of(who)
	if prev == "" {
		return false
	}
	p.by.Remove(who.String())
	p.add(prev, -1)
	return true
}

// Page returns the tally for a page, or nil when nothing was ever recorded
// there. The nil is safe to use: every [Page] read method handles it.
func (b *Board) Page(page string) *Page {
	v := b.pages.Get(page)
	if v == nil {
		return nil
	}
	return v.(*Page)
}

// page returns the tally for a page, creating it if needed.
func (b *Board) page(key string) *Page {
	if p := b.Page(key); p != nil {
		return p
	}
	p := &Page{counts: avl.NewTree(), by: avl.NewTree()}
	b.pages.Set(key, p)
	return p
}

// Pages reports how many pages have ever been reacted to.
func (b *Board) Pages() int { return b.pages.Size() }

// Each visits every page in key order until fn returns true.
func (b *Board) Each(fn func(page string, p *Page) bool) {
	b.pages.Iterate("", "", func(key string, value any) bool {
		return fn(key, value.(*Page))
	})
}

// add changes a bucket by delta, dropping it when it reaches zero so an
// emptied page leaves no residue behind.
func (p *Page) add(key string, delta int) {
	n := p.Count(key) + delta
	if n <= 0 {
		p.counts.Remove(key)
		return
	}
	p.counts.Set(key, n)
}

// Count reports how many addresses currently hold this reaction.
func (p *Page) Count(key string) int {
	if p == nil {
		return 0
	}
	v := p.counts.Get(key)
	if v == nil {
		return 0
	}
	return v.(int)
}

// Total is the number of addresses reacting to this page. It equals the sum of
// every bucket, because an address holds at most one reaction.
func (p *Page) Total() int {
	if p == nil {
		return 0
	}
	return p.by.Size()
}

// Of returns who's current reaction key, or "" when they have none.
func (p *Page) Of(who address) string {
	if p == nil {
		return ""
	}
	v := p.by.Get(who.String())
	if v == nil {
		return ""
	}
	return v.(string)
}

// Last returns the most recent reaction: its palette key, who made it, and the
// height it was made at. The key is "" when the page has never been reacted to.
//
// It can name a reaction that is no longer counted, because [Board.Unreact]
// does not rewind it. That is the honest answer to "what happened here last",
// which is the question the line under the block asks.
func (p *Page) Last() (key string, who address, height int64) {
	if p == nil {
		return "", "", 0
	}
	return p.lastKey, p.lastWho, p.lastAt
}

// ValidPage reports whether page is an acceptable key.
//
// The rule is "a gnoweb render path, and nothing that is not one": at least one
// "/", no empty element, no leading or trailing "/", and only lowercase ASCII
// letters, digits, ".", "-", "_", ":" and "/". That excludes every character a
// markdown escaper exists for, plus every byte above ASCII, so a stored key
// cannot carry a bidi run, a zero-width joiner or an image.
//
// ":" is in the set because a host realm keying the block per article wants the
// path it already serves: "gno.land/r/you/blog:hello-world".
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

// Block renders the embeddable widget: the clickable palette with its counts,
// then one line saying what happened here last.
//
// realmPath is the realm that owns React, given as the full package path from
// its gnomod.toml module line. It is a parameter and not a constant because
// this package is the engine and not the deployment: a second reactions realm,
// on another chain or in a test, renders through the same code.
//
// page appears only in URL positions here: as a txlink query argument, which
// txlink percent-encodes, and inside [PageURL]. Nothing renders it as text, and
// [ValidPage]'s charset is what keeps the [PageURL] form safe. A realm showing
// the key itself must still run it through ui.Inline.
//
// The result ends with a single newline and contains exactly one blank line,
// so it drops into a host realm's Render between two sections without a
// separator of its own.
func Block(realmPath, page string, p *Page) string {
	var b strings.Builder
	for i, key := range order {
		if i > 0 {
			b.WriteString(" ")
		}
		title := palette[key]
		if n := p.Count(key); n > 0 {
			title += " " + strconv.Itoa(n)
		}
		b.WriteString(ui.ActionIn(realmPath, title, "React", "page", page, "key", key))
	}
	b.WriteString("\n\n")
	b.WriteString(md.Italic(Summary(realmPath, page, p)))
	b.WriteString("\n")
	return b.String()
}

// Summary is the one line under the block: the last reaction, and a link to
// the page's own view on the reactions realm. Plain markdown, no wrapper, so a
// caller can put it somewhere else.
func Summary(realmPath, page string, p *Page) string {
	key, who, _ := p.Last()
	if key == "" {
		return "no reactions yet"
	}
	n := p.Total()
	label := strconv.Itoa(n) + " reaction"
	if n != 1 {
		label += "s"
	}
	return "last " + palette[key] + " by " + ui.Addr(who) + " · " +
		md.Link(label, PageURL(realmPath, page))
}

// RealmURL is the gnoweb path of a realm given as a package path.
//
// The chain domain is the first element of a package path and a gnoweb path is
// the rest of it. Derived here rather than read from chain/runtime so this
// package keeps no chain import of its own and the rule stays in one place.
// Returns "" for something that is not a package path.
func RealmURL(realmPath string) string {
	i := strings.Index(realmPath, "/")
	if i < 0 {
		return ""
	}
	return realmPath[i:]
}

// PageURL is the link to one page's view on the reactions realm: [RealmURL]
// with the page as the gnoweb render argument after a colon.
func PageURL(realmPath, page string) string {
	base := RealmURL(realmPath)
	if base == "" {
		return ""
	}
	return base + ":" + page
}
