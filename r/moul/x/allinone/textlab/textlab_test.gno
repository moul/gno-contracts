package textlab

import (
	"testing"

	"gno.land/p/moul/x/daily/levenshtein/v0"
	"gno.land/p/moul/x/daily/soundex/v0"
	"gno.land/p/nt/uassert/v0"
)

// TestRomanOf covers the one package here whose input is a number rather than
// a word, in both directions plus the two ways it can be neither.
func TestRomanOf(t *testing.T) {
	tests := []struct{ in, want string }{
		{"1987", "MCMLXXXVII"},
		{"1", "I"},
		{"3999", "MMMCMXCIX"},
		{"0", "out of range (1..3999)"},
		{"-5", "out of range (1..3999)"},
		{"4000", "out of range (1..3999)"},
		{"MCMLXXXVII", "1987 (read as roman)"},
		{"mcmlxxxvii", "1987 (read as roman)"},
		{"knight", "not a number"},
	}
	for _, tt := range tests {
		uassert.Equal(t, tt.want, romanOf(tt.in), "romanOf("+tt.in+")")
	}
}

// TestTheDisagreement is the claim the realm is built to show, pinned in both
// directions. Measured 2026-09-23; the numbers in the package doc and on the
// page come from here, so if either package changes its mind this fails rather
// than the page quietly stating something false.
func TestTheDisagreement(t *testing.T) {
	// One edit apart, and yet soundex says unrelated: it keys on the first
	// letter, and the silent K changes it.
	uassert.Equal(t, "K523", soundex.Encode("knight"))
	uassert.Equal(t, "N230", soundex.Encode("night"))
	uassert.False(t, soundex.Match("knight", "night"), "different soundex codes")
	uassert.Equal(t, 1, levenshtein.Distance("knight", "night"))
	uassert.Equal(t, 83, levenshtein.Similarity("knight", "night"))

	// And the other way: two edits apart, identical codes.
	uassert.Equal(t, "R163", soundex.Encode("robert"))
	uassert.Equal(t, "R163", soundex.Encode("rupert"))
	uassert.True(t, soundex.Match("robert", "rupert"), "same soundex code")
	uassert.Equal(t, 2, levenshtein.Distance("robert", "rupert"))
}

// TestRomanOfDoesNotAbortOnOrdinaryWords is the defect this realm shipped with
// until a test found it: romannum.FromRoman PANICS on a non-numeral instead of
// returning zero, so the DEFAULT view aborted. "knight" is not a roman numeral,
// and neither is most of what anyone would put in the URL.
func TestRomanOfDoesNotAbortOnOrdinaryWords(t *testing.T) {
	for _, w := range []string{"knight", "night", "a|b", "", "hello world", "MMM!"} {
		uassert.Equal(t, "not a number", romanOf(w), "romanOf("+w+")")
	}
	uassert.True(t, isRomanNumeral("MCMLXXXVII"))
	uassert.False(t, isRomanNumeral("KNIGHT"))
	uassert.False(t, isRomanNumeral(""))
}

// TestInputIsBounded pins the ceiling. levenshtein.Matrix is O(len(a)*len(b)),
// so an unbounded pair out of a URL is a way to make a query expensive for
// whoever serves it.
func TestInputIsBounded(t *testing.T) {
	long := ""
	for i := 0; i < maxInput+1; i++ {
		long += "x"
	}
	uassert.True(t, tooLong(long))
	uassert.False(t, tooLong("knight"))

	out := Render(long)
	uassert.True(t, len(out) < 600, "an over-long input renders a refusal, not a matrix")
}

// TestTableCellsAreEscaped: the input comes out of a URL and lands in a table
// cell, where an unescaped pipe eats a column.
func TestTableCellsAreEscaped(t *testing.T) {
	out := Render("a|b")
	uassert.False(t, contains(out, "| a|b |"), "a raw pipe reached a table cell")
}

func contains(h, n string) bool {
	for i := 0; i+len(n) <= len(h); i++ {
		if h[i:i+len(n)] == n {
			return true
		}
	}
	return false
}

// ExampleRender pins the root view, which is the default word and the "try
// two" list. Nothing here moves with the chain.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # allinone: textlab
	//
	// Eight packages over one input. [source](https://mygnoscan.moul.p2p.team/realm/r/moul/x/allinone/textlab/v0)
	//
	// ## Input: knight
	//
	// | package | answer |
	// | --- | --- |
	// | `x/daily/soundex` | K523 |
	// | `x/daily/rot13` | xavtug |
	// | `x/daily/piglatin` | ightknay |
	// | `x/daily/romannum` | not a number |
	//
	// ## Try two
	//
	// - [knight vs night](/r/moul/x/allinone/textlab/v0:knight/night) (one edit apart, yet soundex says unrelated)
	// - [robert vs rupert](/r/moul/x/allinone/textlab/v0:robert/rupert) (two edits apart, yet soundex says identical)
	// - [1987 as a roman numeral](/r/moul/x/allinone/textlab/v0:1987)
}

// ExampleRender_pair pins the comparison view, which is the realm's whole
// argument: the same pair, judged opposite ways by the two measures.
func ExampleRender_pair() {
	print(Render("knight/night"))
	// Output:
	// # allinone: textlab
	//
	// Eight packages over one input. [source](https://mygnoscan.moul.p2p.team/realm/r/moul/x/allinone/textlab/v0)
	//
	// ## Input: knight
	//
	// | package | answer |
	// | --- | --- |
	// | `x/daily/soundex` | K523 |
	// | `x/daily/rot13` | xavtug |
	// | `x/daily/piglatin` | ightknay |
	// | `x/daily/romannum` | not a number |
	//
	// ## Compared with night
	//
	// | measure | answer |
	// | --- | --- |
	// | `soundex` of knight | K523 |
	// | `soundex` of night | N230 |
	// | sound alike | no |
	// | `levenshtein` distance | 1 |
	// | `levenshtein` similarity | 83% |
}
