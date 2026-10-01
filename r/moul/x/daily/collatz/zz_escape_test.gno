package collatz

import (
	"strings"
	"testing"

	"gno.land/p/moul/md/v0"
	"gno.land/p/nt/uassert/v0"
)

// A path that is not a valid input is echoed back. It is the visitor's text,
// so a backtick in it must not close a code span and let a link through.
func TestInvalidPathIsEscaped(t *testing.T) {
	out := Render("/x` [claim](https://evil.example) `")
	// Still there, but inside a span md.InlineCode widened past its backticks.
	uassert.True(t, strings.Contains(out, md.InlineCode("x` [claim](https://evil.example) `")), out)
}
