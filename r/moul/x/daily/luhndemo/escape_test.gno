package luhndemo

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// payload closes a one-backtick code span and opens an image. Written raw, as
// v0 does, it renders as markup the realm appears to have authored.
const payload = "x` ![p](https:e.io) `y"

// TestRenderEscapesPath pins that the echoed input is a code span it cannot
// close: v0 wrote it between two hand-placed backticks, before luhn.Valid.
func TestRenderEscapesPath(t *testing.T) {
	uassert.Equal(t, "# Luhn Checksum\n\nThe mod-10 check behind card numbers and IMEIs, demoing the [`p/moul/x/daily/luhn`](/p/moul/x/daily/luhn/v0) library.\n\n## ``x` ![p](https:e.io) `y``\n\n**Not valid.**\n\nIt has no usable digits to check.\n", Render("/"+payload))
}
