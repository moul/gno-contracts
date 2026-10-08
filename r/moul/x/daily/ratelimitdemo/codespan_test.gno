package ratelimitdemo

import (
	"strings"
	"testing"
)

// A crafted /addr/<key> path used to close this code span early and render its
// own markdown. md.InlineCode sizes the fence past any backtick run, so the
// payload comes back inside a double fence with the backtick intact.
func TestRenderPathCannotEscapeItsCodeSpan(t *testing.T) {
	out := Render("/addr/a`b")
	if !strings.Contains(out, "``a`b``") {
		t.Fatalf("the fence did not outscan the caller's backtick: %q", out)
	}
}
