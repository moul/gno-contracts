package murmur3demo

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// payload closes a one-backtick code span and opens an image. Written raw it
// would render as markup the realm appears to have authored.
const payload = "x` ![p](https:e.io) `y"

// TestRenderEscapesPath pins that the echoed input stays a code span it
// cannot close: md.InlineCode fences it with as many backticks as it needs,
// and no caller byte ever reaches a table cell.
func TestRenderEscapesPath(t *testing.T) {
	want := "# MurmurHash3 x86_32\n\n" +
		"Austin Appleby's non-cryptographic hash, demoing the " +
		"[`p/moul/x/daily/murmur3`](/p/moul/x/daily/murmur3/v0) library.\n\n" +
		"## ``x` ![p](https:e.io) `y``\n\n" +
		"| seed | hash | bucket of 8 |\n| --- | --- | --- |\n" +
		"| 0 | `1924c6fa` | 2 |\n| 1 | `3ce2d30c` | n/a |\n\n" +
		"Two seeds, two unrelated results: that is how one function becomes a family of them.\n"
	uassert.Equal(t, want, Render("/"+payload))
}

// TestRenderPipeCannotOpenAColumn is the table half of the same worry: a
// caller string full of pipes must not reach a cell at all. It does not, so
// the row count of the arg table stays at two whatever is passed.
func TestRenderPipeCannotOpenAColumn(t *testing.T) {
	got := Render("/a|b|c|d")
	uassert.True(t, !contains(got, "| a|b|c|d |"), "caller text reached a table cell")
	uassert.True(t, contains(got, "## `a|b|c|d`"), "caller text is not in the heading code span")
}

func contains(s, sub string) bool {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}
