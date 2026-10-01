package kitindexdemo

import (
	"strconv"
	"strings"
	"testing"

	"gno.land/p/moul/kit/index/v0"
	"gno.land/p/moul/kit/store/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

var (
	alice = testutils.TestAddress("alice")
	bob   = testutils.TestAddress("bob")
)

// reset puts the realm back to its init() state.
//
// Realm globals persist for the whole test binary and examples run after every
// Test, so without this an ExampleRender's pinned output depends silently on
// which tests ran before it. Assigning the globals directly is allowed here:
// same package, and it crosses nothing.
func reset() {
	notes = store.Named("note")
	byTag = index.Index{}
	byAuthor = index.Index{}
}

func TestPostIndexesInBothDirections(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	id := Post(cross(cur), "gno", "first")

	uassert.Equal(t, 1, notes.Len())
	uassert.Equal(t, 1, byTag.Count("gno"))
	uassert.Equal(t, 1, byAuthor.Count(alice.String()))

	got := byTag.Lookup("gno")
	urequire.Equal(t, 1, len(got))
	uassert.Equal(t, store.ID(id).String(), got[0].String())
}

func TestTagIsNormalisedAtWriteTime(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	Post(cross(cur), "  GNO  ", "mixed case and spaces")

	uassert.Equal(t, 1, byTag.Count("gno"))
	uassert.Equal(t, 1, byTag.Keys())
}

// The tag is an index key AND a path segment, so it is validated rather than
// escaped: a tag carrying a pipe or a slash breaks the table and the URL, not
// only the sentence.
func TestTagRefusals(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))

	for _, tc := range []struct {
		name string
		tag  string
		want string
	}{
		{"empty", "", "a tag is 1 to 24 characters"},
		{"blank", "   ", "a tag is 1 to 24 characters"},
		{"too long", "aaaaaaaaaaaaaaaaaaaaaaaaa", "a tag is 1 to 24 characters"},
		{"a pipe", "a|b", "a tag is [a-z0-9-]"},
		{"a slash", "a/b", "a tag is [a-z0-9-]"},
		{"markdown", "a]b", "a tag is [a-z0-9-]"},
		{"a space inside", "a b", "a tag is [a-z0-9-]"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			uassert.AbortsContains(t, cur, tc.want, func() {
				Post(cross(cur), tc.tag, "body")
			})
		})
	}
	uassert.Equal(t, 0, notes.Len())
}

func TestBodyRefusals(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))

	uassert.AbortsContains(t, cur, "the body is empty", func() {
		Post(cross(cur), "gno", "   ")
	})

	long := ""
	for i := 0; i <= MaxBody; i++ {
		long += "x"
	}
	uassert.AbortsContains(t, cur, "the limit is 280", func() {
		Post(cross(cur), "gno", long)
	})
	uassert.Equal(t, 0, notes.Len())
}

func TestOnlyTheAuthorMayRetract(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	id := Post(cross(cur), "gno", "alice's note")

	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "is not yours", func() {
		Retract(cross(cur), id)
	})
	uassert.Equal(t, 1, notes.Len())

	testing.SetRealm(testing.NewUserRealm(alice))
	Retract(cross(cur), id)
	uassert.Equal(t, 0, notes.Len())
}

// The store and both indexes have to come apart together, or a later Render
// walks ids the store no longer holds.
func TestRetractUnwindsEveryContainer(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	id := Post(cross(cur), "gno", "one")
	Post(cross(cur), "gno", "two")

	Retract(cross(cur), id)

	uassert.Equal(t, 1, notes.Len())
	uassert.Equal(t, 1, byTag.Count("gno"))
	uassert.Equal(t, 1, byAuthor.Count(alice.String()))
}

func TestRetractRefusals(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))

	uassert.AbortsContains(t, cur, "not found", func() { Retract(cross(cur), 99) })
	uassert.AbortsContains(t, cur, "not an id", func() { Retract(cross(cur), 0) })
	uassert.AbortsContains(t, cur, "not an id", func() { Retract(cross(cur), -1) })
}

// A body is a caller's markdown and must not be able to write the page around
// it. ui.Cell is what stops a pipe from opening a column.
func TestARenderedBodyCannotBreakTheTable(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	Post(cross(cur), "gno", "a | b [x](http://evil)")

	got := Render("tag/gno")
	uassert.False(t, strings.Contains(got, "| a | b ["),
		"the raw body must not reach the table")
	uassert.True(t, strings.Contains(got, "\\|"),
		"the pipe must be escaped")
}

func TestRenderOfAnUnknownPage(t *testing.T) {
	reset()
	uassert.True(t, strings.Contains(Render("nope"), "Not found"))
	uassert.True(t, strings.Contains(Render("tag"), "No tag given."))
	uassert.True(t, strings.Contains(Render("author"), "No author given."))
}

// MaxBody bounds one write. These bound the bill, which is the thing the realm
// actually pays.
func TestPerAuthorCap(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	for i := 0; i < MaxPerAuthor; i++ {
		Post(cross(cur), "gno", "note "+strconv.Itoa(i))
	}
	uassert.AbortsContains(t, cur, "the limit is 20", func() {
		Post(cross(cur), "gno", "one too many")
	})

	// Another address is unaffected, which is the whole reason the cap is
	// per author and not only global.
	testing.SetRealm(testing.NewUserRealm(bob))
	Post(cross(cur), "gno", "bob still fits")
	uassert.Equal(t, MaxPerAuthor+1, notes.Len())
}

// Retracting frees a slot, so the cap is not a one-way door.
func TestRetractingFreesASlot(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	first := Post(cross(cur), "gno", "note 0")
	for i := 1; i < MaxPerAuthor; i++ {
		Post(cross(cur), "gno", "note "+strconv.Itoa(i))
	}
	uassert.AbortsContains(t, cur, "the limit is 20", func() {
		Post(cross(cur), "gno", "blocked")
	})

	Retract(cross(cur), first)
	Post(cross(cur), "gno", "now it fits")
	uassert.Equal(t, MaxPerAuthor, notes.Len())
}

// The page number is user input on the Render path. One outside 1..Pages is
// clamped into it, so it never renders an empty board under a footer that
// says "page -1 of 2".
func TestRenderClampsThePageNumber(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	for i := 0; i < PageSize; i++ {
		Post(cross(cur), "t"+strconv.Itoa(i), "x")
	}
	testing.SetRealm(testing.NewUserRealm(bob))
	Post(cross(cur), "t-last", "x")
	urequire.Equal(t, 2, byTag.Pages(PageSize))

	first, last := Render("?page=1"), Render("?page=2")
	uassert.Equal(t, first, Render("?page=-1"))
	uassert.Equal(t, first, Render("?page=0"))
	uassert.Equal(t, last, Render("?page=999"))
	uassert.True(t, strings.Contains(last, "page 2 of 2"))
}

// Links are absolute. gnoweb serves this realm at .../kitindexdemo/v0, so a
// "./kitindexdemo:tag/x" link resolves to .../kitindexdemo/kitindexdemo:tag/x,
// a package that does not exist.
func TestRenderLinksAreAbsolute(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	for i := 0; i <= PageSize; i++ {
		if i == MaxPerAuthor {
			testing.SetRealm(testing.NewUserRealm(bob))
		}
		Post(cross(cur), "t"+strconv.Itoa(i), "x")
	}
	out := Render("")
	uassert.True(t, strings.Contains(out, "](/r/moul/x/kitindexdemo/v0:tag/t0)"), out)
	uassert.True(t, strings.Contains(out, "](/r/moul/x/kitindexdemo/v0:?page=2)"), out)
	uassert.False(t, strings.Contains(out, "](./"), out)
}

// realmURL must follow the module line, or a version bump ships dead links.
func TestRealmURLMatchesTheModule(cur realm, t *testing.T) {
	uassert.Equal(t, "gno.land"+realmURL, cur.PkgPath())
}

// The global cap is what bounds the realm's whole storage bill, so its
// refusal is pinned, and pinned as refusing BEFORE any write: the store and
// both indexes are exactly as full as they were.
func TestTheBoardIsFull(cur realm, t *testing.T) {
	reset()
	for i := 0; i < MaxNotes; i++ {
		notes.Add(&note{Author: bob, Tag: "gno", Body: "x"})
	}
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "the board is full", func() {
		Post(cross(cur), "gno", "one too many")
	})
	uassert.Equal(t, MaxNotes, notes.Len())
	uassert.Equal(t, 0, byTag.Len())
	uassert.Equal(t, 0, byAuthor.Count(alice.String()))
}
