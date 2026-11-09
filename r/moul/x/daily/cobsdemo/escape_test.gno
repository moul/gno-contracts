package cobsdemo

import (
	"strconv"
	"strings"
	"testing"

	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/x/daily/cobs/v0"
	"gno.land/p/nt/uassert/v0"
)

// The path is the visitor's text and it is rendered inside a code span, so a
// backtick in it must not close that span and let a link through. A backslash
// does not escape a backtick inside a span: only a wider fence does, which is
// what md.InlineCode picks.
func TestRenderArgCannotCloseItsCodeSpan(t *testing.T) {
	arg := "x` [claim](https://evil.example) `"
	out := Render("/" + arg)
	uassert.True(t, strings.Contains(out, md.InlineCode(arg)), out)
	uassert.False(t, strings.Contains(out, "`x\\` [claim](https://evil.example) \\``"), out)
}

// Whatever the visitor types, the page's claim is that the frame decodes back
// to it. A page that printed a frame without checking would be advertising a
// round trip it never ran.
func TestRenderArgRoundTrips(t *testing.T) {
	for _, arg := range []string{"hello", "a b", "\xc3\xa9t\xc3\xa9", strings.Repeat("z", 300)} {
		out := Render("/" + arg)
		uassert.True(t, strings.Contains(out, "the same "+strconv.Itoa(len(arg))+" bytes back"), out)
		uassert.False(t, strings.Contains(out, "returned a different payload"), out)
	}
}

// The front page is the one a visitor lands on, and every table on it is
// derived, so a library change that breaks a claim must break this test.
func TestRenderIndexStatesTheOverheadItMeasures(t *testing.T) {
	out := Render("")

	// Five records packed, and the empty one is a record and not nothing.
	uassert.True(t, strings.Contains(out, "gives back 5 records"), out)

	// A thousand zero bytes cost one byte, which is the whole claim.
	uassert.Equal(t, 1001, len(cobs.Encode(strings.Repeat("\x00", 1000))))
	uassert.True(t, strings.Contains(out, "| 1000 | +1 |"), out)

	// And every refusal row names a real error rather than the fallback.
	uassert.False(t, strings.Contains(out, "this table says it should not be"), out)
}

// A payload the path cannot carry is still a payload: the empty argument is
// the index, not a frame of nothing.
func TestRenderEmptyArgIsTheIndex(t *testing.T) {
	uassert.Equal(t, Render(""), Render("/"))
	uassert.True(t, strings.Contains(Render("/"), "Packing records into one string"), Render("/"))
}
