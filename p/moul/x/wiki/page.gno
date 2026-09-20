package wiki

import (
	"time"

	"gno.land/p/moul/ulist/v0"
)

// Protection is a page's edit gate. The engine stores it and reports it; it
// never enforces it, because authority belongs to the realm that owns the
// wiki, not to a pure library. See Wiki.Edit.
type Protection uint8

const (
	Open          Protection = iota // anyone the realm lets through
	SemiProtected                   // realm-defined trusted editors
	Locked                          // stewards only
)

// String returns the protection level's display name.
func (p Protection) String() string {
	switch p {
	case SemiProtected:
		return "semi-protected"
	case Locked:
		return "locked"
	default:
		return "open"
	}
}

// ParseProtection maps a user-supplied level name onto a Protection.
func ParseProtection(s string) (Protection, error) {
	switch s {
	case "open", "":
		return Open, nil
	case "semi", "semi-protected":
		return SemiProtected, nil
	case "locked":
		return Locked, nil
	}
	return Open, ErrBadProtection
}

// Page is one title's history plus the indexes derived from its current
// revision. Revisions live in a ulist: append is O(1) and does not rewrite the
// existing entries, which matters when a popular page accumulates thousands of
// edits and every write would otherwise re-serialize the whole slice.
type Page struct {
	Title      Title
	Protection Protection
	Created    time.Time
	Blanked    bool // a steward blanked it; history is retained

	revs *ulist.List // *Revision, oldest first
	head *Revision

	redirect string   // target title, "" when this page is not a redirect
	links    []string // outgoing wikilink target keys of head
	cats     []string // category keys head belongs to
}

// Head returns the current revision, or nil for a page with no revisions.
func (p *Page) Head() *Revision { return p.head }

// NumRevisions returns how many revisions the page has.
func (p *Page) NumRevisions() int { return p.revs.Size() }

// Redirect returns the title this page redirects to, or "" if it does not.
func (p *Page) Redirect() string { return p.redirect }

// Body returns the current text and whether it is held on chain.
func (p *Page) Body() (string, bool) {
	if p.head == nil {
		return "", false
	}
	return p.head.Body()
}

// Revision returns the revision with the given id, or nil.
func (p *Page) Revision(id uint64) *Revision {
	var found *Revision
	p.revs.Iterator(0, p.revs.Size()-1, func(_ int, v any) bool {
		r := v.(*Revision)
		if r.ID == id {
			found = r
			return true
		}
		return false
	})
	return found
}

// History returns up to count revisions, newest first, skipping the newest
// offset of them.
func (p *Page) History(offset, count int) []*Revision {
	out := []*Revision{}
	if count <= 0 {
		return out
	}
	size := p.revs.Size()
	// Walk backwards: index size-1 is the newest.
	for i := size - 1 - offset; i >= 0 && len(out) < count; i-- {
		out = append(out, p.revs.MustGet(i).(*Revision))
	}
	return out
}

// Contributors returns the distinct authors of the page, oldest edit first.
func (p *Page) Contributors() []address {
	seen := map[string]bool{}
	out := []address{}
	p.revs.Iterator(0, p.revs.Size()-1, func(_ int, v any) bool {
		r := v.(*Revision)
		if !seen[r.Author.String()] {
			seen[r.Author.String()] = true
			out = append(out, r.Author)
		}
		return false
	})
	return out
}
