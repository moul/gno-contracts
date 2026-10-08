package grants

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
)

// A crafted URL path used to close this code span early and render its own
// markdown. md.InlineCode sizes the fence past any backtick run, so the payload
// comes back inside a double fence with the backtick intact.
func TestRenderPathCannotEscapeItsCodeSpan(t *testing.T) {
	out := Renderer{Program: NewProgram("ugnot", testutils.TestAddress("a")), Title: "T", Link: "/r/x/v0"}.Render("a`b")
	if !strings.Contains(out, "``a`b``") {
		t.Fatalf("the fence did not outscan the caller's backtick: %q", out)
	}
}
