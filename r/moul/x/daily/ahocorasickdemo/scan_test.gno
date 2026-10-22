package ahocorasickdemo

import (
	"strings"
	"testing"

	"gno.land/p/moul/md/v0"
	"gno.land/p/nt/uassert/v0"
)

// The path is the visitor's text and it is echoed inside a code span, so a
// backtick in it must not close that span and let a link through. A backslash
// does not escape a backtick inside a span: only a wider fence does, which is
// what md.InlineCode picks.
func TestRenderArgCannotCloseItsCodeSpan(t *testing.T) {
	arg := "x` [claim](https://evil.example) `"
	out := Render("/" + arg)
	uassert.True(t, strings.Contains(out, md.InlineCode(arg)), out)
	uassert.False(t, strings.Contains(out, "`x\\` [claim](https://evil.example) \\``"), out)
}

// The match table reports offsets and dictionary words, never a slice of the
// scanned text, so the argument reaches the page exactly once: in the heading
// that echoes it. A pipe in it cannot open a column that is not there.
func TestRenderEchoesTheArgumentOnlyOnce(t *testing.T) {
	out := Render("/the|evil")
	uassert.Equal(t, 1, strings.Count(out, "evil"))
	uassert.True(t, strings.Contains(out, "| `0` | `3` | `the` |"), out)
}

// A text with nothing from the dictionary gets a sentence, not an empty table:
// an empty table reads as a broken page rather than as an answer.
func TestRenderSaysWhenNothingMatched(t *testing.T) {
	out := Render("/zzz")
	uassert.True(t, strings.Contains(out, "No pattern occurs in it."), out)
	uassert.False(t, strings.Contains(out, "| start | end | pattern |"), out)
}

// Whitespace is not trimmed: trimming would report offsets into a string the
// visitor did not submit. The leading space shifts every offset by one.
func TestRenderDoesNotTrim(t *testing.T) {
	out := Render("/ the")
	uassert.True(t, strings.Contains(out, "| `1` | `4` | `the` |"), out)
}

// The realm holds no state, so two renders of the same path agree. This is
// what makes the pinned example meaningful rather than a snapshot of whichever
// test ran before it.
func TestRenderIsDeterministic(t *testing.T) {
	uassert.Equal(t, Render(""), Render(""))
	uassert.Equal(t, Render("/thermos"), Render("/thermos"))
}
