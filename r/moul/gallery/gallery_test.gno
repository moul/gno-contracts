package gallery

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestRenderIndexMarkdown(t *testing.T) {
	out := Render("")
	uassert.True(t, strings.Contains(out, "# moul's gallery"), "heading")
	uassert.True(t, strings.Contains(out, "```"), "the banner is fenced in markdown")
	uassert.True(t, strings.Contains(out, "| Piece |"), "a real markdown table")
	// The path is spelled out rather than taken from realmPath: a test that
	// reads the same constant the code does would pass with the version
	// dropped, which is the exact regression this pins.
	for _, p := range catalog() {
		uassert.True(t, strings.Contains(out, "/r/moul/gallery/v0:piece/"+p.Slug), p.Slug+" is linked")
	}
}

// The two targets are different documents, not one with characters deleted.
func TestTextTargetStripsMarkdownAndDefersLinks(t *testing.T) {
	out := Render("piece/millipede?fmt=txt")

	uassert.False(t, strings.Contains(out, "```"), "no code fences")
	uassert.False(t, strings.Contains(out, "**"), "no bold markers")
	uassert.False(t, strings.Contains(out, "]("), "no inline link syntax")
	uassert.False(t, strings.Contains(out, "\n#"), "no heading hashes")

	// A heading is underlined instead.
	uassert.True(t, strings.Contains(out, "millipede\n========="), "underlined heading")
	// And the URL is a numbered footnote, not inline noise.
	uassert.True(t, strings.Contains(out, "the source realm [1]"), "inline marker")
	uassert.True(t, strings.Contains(out, "\nLinks:\n  [1] https://gno.land/r/moul/demo/millipede/v0"), "footnote block")
}

func TestTextTableColumnsLineUp(t *testing.T) {
	out := Render("?fmt=txt")
	var header, rule string
	for _, line := range strings.Split(out, "\n") {
		if strings.HasPrefix(line, "  Piece ") {
			header = line
		}
		if strings.HasPrefix(line, "  ---") {
			rule = line
		}
	}
	uassert.True(t, header != "", "found the header")
	uassert.True(t, rule != "", "found the rule")

	// Every column boundary in the rule is a pair of spaces in the header at
	// the same rune offset. That is the property an unpadded pipe table does
	// not have, and the reason the text target has its own table at all.
	uassert.Equal(t, gutters(rule), gutters(header), "columns start at the same offsets")
}

// gutters returns the rune offsets at which a column starts: a non-space
// preceded by at least two spaces. Measuring where the PADDING starts instead
// would compare "Piece" against eleven dashes and report a difference that is
// not one.
func gutters(s string) string {
	r := []rune(s)
	out := ""
	for i := 2; i < len(r); i++ {
		if r[i] != ' ' && r[i-1] == ' ' && r[i-2] == ' ' {
			out += itoa(i) + ","
		}
	}
	return out
}

func TestArtIsNeverEscapedOrWrapped(t *testing.T) {
	// The millipede is box-drawing and parentheses. A text target that ran it
	// through an escaper or a wrapper would ruin it, and it would still look
	// like a picture, which is what makes this worth pinning.
	out := Render("piece/millipede?fmt=txt")
	uassert.True(t, strings.Contains(out, "╚═(███)═╝"), "art survives verbatim")
	uassert.False(t, strings.Contains(out, "\\("), "no escaping")
}

func TestUnknownPiece(t *testing.T) {
	uassert.True(t, strings.Contains(Render("piece/nope"), "no piece called nope"), "markdown 404")
	uassert.True(t, strings.Contains(Render("piece/nope?fmt=txt"), "No piece called nope."), "text 404")
	// An empty slug is the index, not a 404.
	uassert.True(t, strings.Contains(Render("piece/"), "# moul's gallery"), "empty slug falls back to the index")
}

func TestLinkedPiecesSayWhyTheyAreNotRendered(t *testing.T) {
	p, ok := find("asciiart")
	uassert.True(t, ok, "found")
	uassert.False(t, p.Live(), "asciiart is private = true, so it cannot be imported")

	out := Render("piece/asciiart")
	uassert.True(t, strings.Contains(out, "cannot import the source"), "says so rather than showing nothing")
}

func TestEveryPieceRenders(t *testing.T) {
	for _, p := range catalog() {
		out := Render("piece/" + p.Slug)
		uassert.True(t, strings.Contains(out, p.Title), p.Slug+" markdown")
		uassert.True(t, len(Render("piece/"+p.Slug+"?fmt=txt")) > 0, p.Slug+" text")
	}
}

func TestWrapKeepsLongWordsIntact(t *testing.T) {
	long := "see gno.land/r/g17khqpukees4237dtn3astzapmp462vjhsz6st4/settlers/nft now"
	got := wrap(long, 20)
	// A path is worse broken than wide, so it overflows rather than splitting.
	uassert.True(t, strings.Contains(got, "gno.land/r/g17khqpukees4237dtn3astzapmp462vjhsz6st4/settlers/nft"), "unbroken")
	uassert.Equal(t, 3, len(strings.Split(got, "\n")), "three lines")
}
