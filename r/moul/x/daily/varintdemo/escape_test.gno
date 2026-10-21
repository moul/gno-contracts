package varintdemo

import (
	"strings"
	"testing"

	"gno.land/p/moul/md/v0"
	"gno.land/p/nt/uassert/v0"
)

// The path is the visitor's text and it is rendered inside a code span, so a
// backtick in it must not close that span and let a link through. A
// backslash does not escape a backtick inside a span: only a wider fence
// does, which is what md.InlineCode picks.
func TestRenderArgCannotCloseItsCodeSpan(t *testing.T) {
	arg := "x` [claim](https://evil.example) `"
	out := Render("/" + arg)
	uassert.True(t, strings.Contains(out, md.InlineCode(arg)), out)
	uassert.False(t, strings.Contains(out, "`x\\` [claim](https://evil.example) \\``"), out)
}

// A value above MaxInt64 is one this codec carries: the unsigned line is
// rendered, so the page must not then say the codec cannot carry it.
func TestRenderMaxUint64DoesNotContradictItself(t *testing.T) {
	out := Render("/18446744073709551615")
	uassert.True(t, strings.Contains(out, "ff ff ff ff ff ff ff ff ff 01"), out)
	uassert.False(t, strings.Contains(out, "Not an integer"), out)
}

// Neither parse succeeding is the only case that message belongs to.
func TestRenderRejectsNonInteger(t *testing.T) {
	out := Render("/notanumber")
	uassert.True(t, strings.Contains(out, "Not an integer"), out)
}

// Whitespace is not trimmed: trimming would launder an input the parsers
// refuse into a clean encoding of a value nobody submitted.
func TestRenderDoesNotTrim(t *testing.T) {
	out := Render("/ 300 ")
	uassert.True(t, strings.Contains(out, "Not an integer"), out)
}
