package render

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// payload closes a one-backtick code span and opens an image. Written raw, as
// v0 does, it renders as markup the realm appears to have authored.
const payload = "x` ![p](https:e.io) `y"

// TestRenderEscapesGreeting pins that the name in greetings/<name> is escaped:
// v0 returned "Welcome, X` ![p](https:e.io) `y!" with a live image in it.
func TestRenderEscapesGreeting(t *testing.T) {
	uassert.Equal(t, "Welcome, X\\` \\!\\[P\\]\\(Https:E\\.Io\\) \\`Y!", Render("greetings/"+payload))
}
