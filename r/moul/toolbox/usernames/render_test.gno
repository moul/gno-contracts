package usernames

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestRenderHome(cur realm, t *testing.T) {
	seed(cur, t)

	got := Render("")
	uassert.True(t, strings.Contains(got, "[toolbox](/r/moul/toolbox)"))
	uassert.True(t, strings.Contains(got, "# Usernames"))
	uassert.True(t, strings.Contains(got, `<gno-form path="lookup">`))
	uassert.True(t, strings.Contains(got, `<gno-input name="q"`))
	uassert.True(t, strings.Contains(got, "gnokey query vm/qeval"))
}

func TestRenderResultByPathAndByQuery(cur realm, t *testing.T) {
	seed(cur, t)

	byPath := Render("moul")
	byQuery := Render("lookup?q=moul")
	uassert.Equal(t, byPath, byQuery)
	uassert.True(t, strings.Contains(byPath, "[@moul](/u/moul)"))
	uassert.True(t, strings.Contains(byPath, moulAddr.String()))
	uassert.True(t, strings.Contains(byPath, "Canonical"))
}

func TestRenderResultByAddress(cur realm, t *testing.T) {
	seed(cur, t)

	got := Render(moulAddr.String())
	uassert.True(t, strings.Contains(got, "[@moul](/u/moul)"))
}

func TestRenderNotFound(cur realm, t *testing.T) {
	seed(cur, t)

	got := Render("nobodyholdsthis")
	uassert.True(t, strings.Contains(got, "Nothing registered under"))
	uassert.True(t, strings.Contains(got, "deleted"))

	addr := Render(plainAddr.String())
	uassert.True(t, strings.Contains(addr, "That is a valid address"))
	uassert.True(t, strings.Contains(addr, "/r/gnoland/users"))
}

func TestRenderTooManyParts(cur realm, t *testing.T) {
	seed(cur, t)

	got := Render("a/b")
	uassert.True(t, strings.Contains(got, "Nothing registered under"))
}

// TestRenderEscapesInput: the query parameter is attacker-chosen and a live
// realm can never be fixed, so this is the test that must be seen to fail
// before it is believed.
//
// The property is that the echo is INERT, not that particular bytes are
// absent. A code span makes link syntax inert without removing it, so an
// assertion that the substring is gone would pass for the wrong reason under
// one escaper and fail for the wrong reason under the other.
func TestRenderEscapesInput(cur realm, t *testing.T) {
	seed(cur, t)

	const link = "[x](javascript:alert(1))"
	got := Render("lookup?q=" + "%5Bx%5D%28javascript%3Aalert%281%29%29")
	uassert.True(t, strings.Contains(got, "`"+link+"`"))
	uassert.False(t, strings.Contains(got, " "+link+" "))

	// A backtick in the input cannot close the span early: the fence widens.
	tick := Render("lookup?q=a%60b")
	uassert.True(t, strings.Contains(tick, "``"))
	uassert.False(t, strings.Contains(tick, "under `a`b`."))

	// A heading marker cannot open a block of its own: the echo stays on the
	// line it was put on.
	head := Render("lookup?q=%0A%23%20pwned")
	uassert.False(t, strings.Contains(head, "\n# pwned"))
}

// TestRenderOmitsTheCommandForUnsafeInput: nothing escapes inside a fenced
// code block, so an input that cannot go in one does not get one.
func TestRenderOmitsTheCommandForUnsafeInput(cur realm, t *testing.T) {
	seed(cur, t)

	uassert.True(t, strings.Contains(Render("moul"), "gnokey query vm/qeval"))
	uassert.False(t, strings.Contains(Render("lookup?q=a%60b"), "gnokey query vm/qeval"))
}

func TestRenderNeverEmitsTwoBlankLines(cur realm, t *testing.T) {
	seed(cur, t)

	for _, path := range []string{"", "moul", "nobodyholdsthis", moulAddr.String(), "a/b"} {
		uassert.False(t, strings.Contains(Render(path), "\n\n\n"))
	}
}
