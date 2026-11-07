package punycodedemo

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// payload closes a one-backtick code span and opens an image. Written raw, it
// renders as markup the realm appears to have authored.
const payload = "x` ![p](https:e.io) `y"

// TestRenderEscapesArg pins the escaping of the caller's argument. The echoed
// domain is the one that matters: EncodeDomain passes an all-ASCII label
// straight through, so without ui.Inline the payload would reach a permanent
// page byte for byte.
func TestRenderEscapesArg(t *testing.T) {
	uassert.Equal(t, "# Punycode\n\nRFC 3492 bootstring, demoing the [`p/moul/x/daily/punycode`](/p/moul/x/daily/punycode/v0) library.\n\n## x\\` \\!\\[p\\]\\(https:e\\.io\\) \\`y\n\n- label: x\\` \\!\\[p\\]\\(https:e\\.io\\) \\`y\\-\n- domain: x\\` \\!\\[p\\]\\(https:e\\.io\\) \\`y\n", Render("/"+payload))
}
