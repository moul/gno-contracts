package levenshteindemo

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// payload closes a one-backtick code span and opens an image. Written raw, as
// v0 does, it renders as markup the realm appears to have authored.
const payload = "x` ![p](https:e.io) `y"

// TestRenderEscapesWords pins that both words are code spans they cannot close,
// and that each rune in the DP table is a cell it cannot split: v0 wrote the
// words between hand-placed backticks and every rune raw, so a "|" opened a
// column and a backtick unbalanced the row.
func TestRenderEscapesWords(t *testing.T) {
	uassert.Equal(t, "# Levenshtein distance\n\nTransforming **``a`|``** → **`[b](https:e.io)`**\n\n- **Edit distance:** `15` single-character edits (insert / delete / substitute)\n- **Similarity:** `0%`\n\n## DP table\n\nEach cell `d[i][j]` is the distance between the first *i* runes of ``a`|`` and the first *j* runes of `[b](https:e.io)`. The bottom-right cell is the answer.\n\n|   | ε | \\[ | b | \\] | \\( | h | t | t | p | s | : | e | \\. | i | o | \\) |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|\n| **ε** | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 |\n| **a** | 1 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 |\n| **\\`** | 2 | 2 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 |\n| **\\|** | 3 | 3 | 3 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 |\n\n[← back](/r/moul/x/daily/levenshteindemo/v1)\n", Render("/a`|/[b](https:e.io)"))
}
