package piglatindemo

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// payload closes a one-backtick code span and opens an image. Written raw, as
// v0 does, it renders as markup the realm appears to have authored.
const payload = "x` ![p](https:e.io) `y"

// TestRenderEscapesSentence pins that the sentence and its translation are
// escaped inside their blockquotes: v0 wrote both raw, so an image or a link
// in the path rendered, and Translate keeps punctuation in place.
func TestRenderEscapesSentence(t *testing.T) {
	uassert.Equal(t, "# Pig Latin\n\n**Original:**\n\n> x\\` \\!\\[p\\]\\(https:e\\.io\\) \\`y\n\n**Pig Latin:**\n\n> xay\\` \\!\\[e\\.iop\\]\\(https:ay\\) \\`yay\n\n---\n\n[← rules & examples](/r/moul/x/daily/piglatindemo/v1)\n", Render("/"+payload))
}
