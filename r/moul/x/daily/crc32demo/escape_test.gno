package crc32demo

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// payload closes a one-backtick code span and opens an image. Written raw, as
// v0 does, it renders as markup the realm appears to have authored.
const payload = "x` ![p](https:e.io) `y"

// TestRenderEscapesPath pins that the echoed input is a code span it cannot
// close: v0 wrote it between two hand-placed backticks.
func TestRenderEscapesPath(t *testing.T) {
	uassert.Equal(t, "# CRC-32\n\nThe IEEE checksum behind zip, gzip and PNG, demoing the [`p/moul/x/daily/crc32`](/p/moul/x/daily/crc32/v0) library.\n\n## ``x` ![p](https:e.io) `y``\n\n`d9680653`\n", Render("/"+payload))
}
