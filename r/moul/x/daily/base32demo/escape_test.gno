package base32demo

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
	uassert.Equal(t, "# Base32\n\nRFC 4648 and Crockford, demoing the [`p/moul/x/daily/base32`](/p/moul/x/daily/base32/v0) library.\n\n## ``x` ![p](https:e.io) `y``\n\n- RFC 4648: `PBQCAIK3OBOSQ2DUORYHGOTFFZUW6KJAMB4Q====`\n- Crockford: `F1G208AVE1EJGT3MEHR76EK55SMPYA90C1WG`\n", Render("/"+payload))
}
