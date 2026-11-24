package jarowinklerdemo

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// payload closes a one-backtick code span and opens an image. Written raw it
// would render as markup the realm appears to have authored.
const payload = "x` ![p](https:e.io) `y"

// TestRenderEscapesBothArguments pins that neither half of the path escapes
// its context: the heading fences each one in a code span it cannot close,
// and every table cell goes through ui.Cell, which a code span alone would
// not have done.
func TestRenderEscapesBothArguments(t *testing.T) {
	want := "# Jaro-Winkler\n" +
		"\n" +
		"How much of two strings lines up, demoing the [`p/moul/x/daily/jarowinkler`](/p/moul/x/daily/jarowinkler/v0) library. Scores are integers out of 1000000, so no float ever reaches the chain.\n" +
		"\n" +
		"## ``x` ![p](https:e.io) `y`` vs `a|b`\n" +
		"\n" +
		"| metric | score | out of 1000000 |\n" +
		"| --- | --- | --- |\n" +
		"| Jaro | 0.00% | 0 |\n" +
		"| Jaro-Winkler | 0.00% | 0 |\n" +
		"\n" +
		"|  | value |  |\n" +
		"| --- | --- | --- |\n" +
		"| runes in a | 22 | x\\` \\!\\[p\\]\\(https:e\\.io\\) \\`y |\n" +
		"| runes in b | 3 | a\\|b |\n" +
		"| window | 10 | how far apart two runes may still match |\n" +
		"| matches | 0 | runes with a partner inside the window |\n" +
		"| transpositions | 0 | matched pairs that arrived in the wrong order |\n" +
		"| common prefix | 0 | leading runes, of which Winkler counts four |\n" +
		"\n" +
		"Nothing matched, so the score is 0.\n" +
		"\n" +
		"[← back](/r/moul/x/daily/jarowinklerdemo/v0)\n"
	uassert.Equal(t, want, Render("/"+payload+"/a|b"))
}

// TestRenderPipeCannotOpenAColumn is the table half of the same worry: a
// caller rune that is a "|" reaches both the stats table and the per-rune
// pairing, and must stay one cell in each.
func TestRenderPipeCannotOpenAColumn(t *testing.T) {
	want := "# Jaro-Winkler\n" +
		"\n" +
		"How much of two strings lines up, demoing the [`p/moul/x/daily/jarowinkler`](/p/moul/x/daily/jarowinkler/v0) library. Scores are integers out of 1000000, so no float ever reaches the chain.\n" +
		"\n" +
		"## `a|b` vs `a|b`\n" +
		"\n" +
		"| metric | score | out of 1000000 |\n" +
		"| --- | --- | --- |\n" +
		"| Jaro | 100.00% | 1000000 |\n" +
		"| Jaro-Winkler | 100.00% | 1000000 |\n" +
		"\n" +
		"|  | value |  |\n" +
		"| --- | --- | --- |\n" +
		"| runes in a | 3 | a\\|b |\n" +
		"| runes in b | 3 | a\\|b |\n" +
		"| window | 0 | how far apart two runes may still match |\n" +
		"| matches | 3 | runes with a partner inside the window |\n" +
		"| transpositions | 0 | matched pairs that arrived in the wrong order |\n" +
		"| common prefix | 3 | leading runes, of which Winkler counts four |\n" +
		"\n" +
		"| # | a | b |  |\n" +
		"| --- | --- | --- | --- |\n" +
		"| 1 | a | a |  |\n" +
		"| 2 | \\| | \\| |  |\n" +
		"| 3 | b | b |  |\n" +
		"\n" +
		"[← back](/r/moul/x/daily/jarowinklerdemo/v0)\n"
	uassert.Equal(t, want, Render("/a|b/a|b"))
}
