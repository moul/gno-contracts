package hmacdemo

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// payload closes a one-backtick code span and opens an image. Written raw it
// renders as markup this realm would appear to have authored.
const payload = "x` ![p](https:e.io) `y"

// TestRenderEscapesPath pins that the echoed message stays inside a code span
// it cannot close: md.InlineCode widened the fence to two backticks.
func TestRenderEscapesPath(t *testing.T) {
	uassert.Equal(t, "# HMAC-SHA-256\n\nKey `moul`, message ``x` ![p](https:e.io) `y``.\n\n`4aba0c44ba2cd754a409d2e68e7e2323f401976f2181226a4f57971845b12a7e`\n\n[back to the demo](/r/moul/x/daily/hmacdemo/v0)\n", Render("/"+payload))
}

// TestRenderDoesNotEmitTheImage is the assertion that would survive a change
// to the surrounding prose: whatever else moves, the payload's image markup
// must never reach the page outside a code span.
func TestRenderDoesNotEmitTheImage(t *testing.T) {
	out := Render("/" + payload)
	fenced := "``" + payload + "``"
	if !strings.Contains(out, fenced) {
		t.Errorf("payload is not inside a widened code span: %q", out)
	}
	if strings.Contains(strings.ReplaceAll(out, fenced, ""), "![p](") {
		t.Error("image markup reached the page outside the code span")
	}
}
