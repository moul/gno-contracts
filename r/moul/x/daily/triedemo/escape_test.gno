package triedemo

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// payload closes a one-backtick code span and opens an image. Written raw, as
// v0 does, it renders as markup the realm appears to have authored.
const payload = "x` ![p](https:e.io) `y"

// TestRenderEscapesPrefix pins that a prefix matching nothing is echoed as a
// code span it cannot close, in the heading and in the miss line: v0 wrote it
// between hand-placed backticks in both.
func TestRenderEscapesPrefix(t *testing.T) {
	uassert.Equal(t, "# Trie Autocomplete\n\nA prefix tree over a 55-word dictionary, demoing the [`p/moul/x/daily/trie`](/p/moul/x/daily/trie/v0) library.\n\n## Completions for ``x` ![p](https:e.io) `y``\n\n_No word starts with ``x` ![p](https:e.io) `y``._\n\n> Try `/co`, `/gno`, `/tr` or `/re`.\n", Render("/"+payload))
}
