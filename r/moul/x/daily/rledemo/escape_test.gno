package rledemo

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// payload closes a one-backtick code span and opens an image. Written raw, as
// v0 does, it renders as markup the realm appears to have authored.
const payload = "x` ![p](https:e.io) `y"

// TestRenderEscapesInput pins that an accepted input is echoed as a code span
// it cannot close, and so is its encoding, which carries the backtick through.
func TestRenderEscapesInput(t *testing.T) {
	uassert.Equal(t, "# Run-Length Encoding\n\n`<count><char>` pairs, demoing the [`p/moul/x/daily/rle`](/p/moul/x/daily/rle/v0) library.\n\n## ``x` ![p](https:e.io) `y``\n\n- encoded: ``1x1`1 1!1[1p1]1(1h2t1p1s1:1e1.1i1o1)1 1`1y``\n- size: **190%**\n- round-trips: ✅\n", Render("/"+payload))
}

// TestRenderRejectsBeforeEcho pins the order: rle refuses digits, and the
// refused input is never written back. v0 wrote the heading first.
func TestRenderRejectsBeforeEcho(t *testing.T) {
	uassert.Equal(t, "# Run-Length Encoding\n\n`<count><char>` pairs, demoing the [`p/moul/x/daily/rle`](/p/moul/x/daily/rle/v0) library.\n\n_rle: input must not contain digits_\n", Render("/1"+payload))
}
