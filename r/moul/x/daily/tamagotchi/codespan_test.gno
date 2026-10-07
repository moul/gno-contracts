package tamagotchi

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// The not-found branch echoes the visitor's URL path into a code span. Built by
// hand, a backtick in the path closed the span early and everything after it
// rendered as markdown on a gno.land page. md.InlineCode sizes the fence past
// any backtick run in the content, so the payload must come back wrapped in a
// DOUBLE fence, with the backtick intact inside it. Asserting on the payload
// itself rather than on any double fence in the page: an earlier version of
// this test passed on an unrelated span elsewhere in the output.
func TestRenderPathCannotEscapeItsCodeSpan(t *testing.T) {
	out := Render("/a`b")
	fenced := strings.Contains(out, "``a`b``") || strings.Contains(out, "``/a`b``")
	uassert.True(t, fenced,
		"the fence did not outscan the caller's backtick, so the span closes early")
}
