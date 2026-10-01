package kitindexdemo

import (
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
