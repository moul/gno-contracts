package sha1demo

import (
	"strconv"
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/moul/x/daily/sha1/v0"
)

// payload closes a code span and opens an image: written raw it would render
// as markup this realm appears to have authored.
const payload = "x` ![p](https:e.io) `y"

// TestRenderEscapesPath pins that the echoed input comes back escaped and that
// the digest shown is still the digest of the raw bytes: escaping the display
// must not change what was hashed.
func TestRenderEscapesPath(t *testing.T) {
	out := Render("/" + payload)
	uassert.False(t, strings.Contains(out, "![p](https:e.io)"), "the image must not survive escaping")
	uassert.True(t, strings.Contains(out, "`"+sha1.SumHex(payload)+"`"), "the digest must be of the raw input")
	uassert.True(t, strings.Contains(out, "`"+sha1.GitBlobID(payload)+"`"), "the blob id must be of the raw input")
}

// TestRenderHashesWholePath pins that a slash or surrounding space is part of
// the input: ":src/main.go" must hash all of "src/main.go", not "src".
func TestRenderHashesWholePath(t *testing.T) {
	for _, in := range []string{"src/main.go", " padded ", "a/b/c"} {
		out := Render("/" + in)
		uassert.True(t, strings.Contains(out, "`"+sha1.SumHex(in)+"`"), "digest of "+in)
		uassert.True(t, strings.Contains(out, "`"+strconv.Itoa(len(in))+"`"), "byte count of "+in)
	}
}
