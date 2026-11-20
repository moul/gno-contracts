package ascii85demo

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// payload closes a one-backtick code span and opens an image. Written raw it
// renders as markup the realm appears to have authored.
const payload = "x` ![p](https:e.io) `y"

// TestRenderEscapesPath pins that the echoed input cannot author markup: the
// heading is escaped inline, so the image never opens.
func TestRenderEscapesPath(t *testing.T) {
	got := Render("/" + payload)
	uassert.False(t, strings.Contains(got, "## "+payload), "the raw payload is never a heading")
	uassert.True(t, strings.Contains(got, "## x\\` \\!\\[p\\]\\(https:e\\.io\\) \\`y"), "the heading is escaped")
}

// TestRenderEscapesBacktickInOutput is the case this codec's alphabet makes
// real, and the reason the encoded forms are not wrapped in hand-placed
// backticks. The backtick is character 96, inside the '!' to 'u' range ascii85
// encodes into, so an encoded value can carry one and close a one-backtick
// code span. Encode("i") is "B`", the shortest input whose output does.
func TestRenderEscapesBacktickInOutput(t *testing.T) {
	got := Render("/i")
	uassert.True(t, strings.Contains(got, "| bare | `` B` `` |"), "the span is widened past the backtick it holds")
	uassert.False(t, strings.Contains(got, "| bare | `B`` |"), "a one-backtick span is never emitted around it")
}
