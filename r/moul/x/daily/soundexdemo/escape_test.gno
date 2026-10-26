package soundexdemo

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// payload closes a one-backtick code span and opens an image. Written raw, as
// v0 does, it renders as markup the realm appears to have authored.
const payload = "x` ![p](https:e.io) `y"

// TestRenderEscapesPath pins that the echoed name is a code span it cannot
// close: v0 wrote it between two hand-placed backticks (gno-contracts#359).
func TestRenderEscapesPath(t *testing.T) {
	uassert.Equal(t, "# Soundex\n\nPhonetic keys for English names, demoing the [`p/moul/x/daily/soundex`](/p/moul/x/daily/soundex/v0) library.\n\n## ``x` ![p](https:e.io) `y``\n\nkey: **X131** (normalized: `XPHTTPSEIOY`)\n", Render("/"+payload))
}
