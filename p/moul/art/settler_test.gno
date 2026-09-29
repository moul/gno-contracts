package art

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// Settler #25, read from mainnet on 2026-09-29 and transcribed one character
// per palette index (0-9 then a-j). 32x32, 20 colours.
//
// It is here because the package's central claim is about real indexed art and
// a synthetic two-colour fixture cannot test it: the interesting thing about a
// sprite is how many near-luminance colours it carries, and that is a property
// of art somebody drew.
//
// gno.land/r/g17khqpukees4237dtn3astzapmp462vjhsz6st4/settlers/nft:token/25
// The Settlers art is dedicated to the public domain under CC0 1.0.
var settler25Pal = Palette{"#f3e3c9", "#2a1a2e", "#ffb45a", "#b5601c", "#f08a2a", "#b57650", "#d99a6c", "#7f5234", "#1b1626", "#f08c7c", "#ffb0a0", "#c8645a", "#a8744e", "#573622", "#5fb0e8", "#2b649a", "#3f8fd1", "#6b3f22", "#6a4126", "#46271a"}

var settler25Rows = []string{
	"00000000000000011000000000000000",
	"00000000000000123100000000000000",
	"00000000000000144100000000000000",
	"00000000000001244310000000000000",
	"00000000000001444410000000000000",
	"00000000000012444431000000000000",
	"00000000000014444441000000000000",
	"00000000000124444443100000000000",
	"00000000000144444444100000000000",
	"00000000001244444444310000000000",
	"00000000001444444444410000000000",
	"00000000124444444444443100000000",
	"00000000133333333333333100000000",
	"00000000001555555555510000000000",
	"00000000001677766777610000000000",
	"00000000016686666668661000000000",
	"00000000156686699668665100000000",
	"00000000001666a99b66610000000000",
	"0000000001c777bbbb777d1000000000",
	"0000000011c7777777777d1100000000",
	"00000001e1c777d77d777d1f10000000",
	"00000001eg1c77d77d77d1gf10000000",
	"00000001eg1c7d7777d7d1gf10000000",
	"00000016egg1c7d77d7d1ggf61000000",
	"00000015egg1c777777d1ggf51000000",
	"00000001hhhh1c7dd7d1hhhh10000000",
	"00000001egggg1c77d1ggggf10000000",
	"00000001ffffff1cd1ffffff10000000",
	"0000000001iiiii11iiiii1000000000",
	"0000000001iiiii11iiiii1000000000",
	"0000000001jjjjj11jjjjj1000000000",
	"00000000011111111111111000000000",
}

func settler25() *Pix {
	p := NewPix(len(settler25Rows[0]), len(settler25Rows), settler25Pal)
	for y, row := range settler25Rows {
		for x, r := range row {
			var i int
			if r >= '0' && r <= '9' {
				i = int(r - '0')
			} else {
				i = int(r-'a') + 10
			}
			p.Set(x, y, uint8(i))
		}
	}
	return p
}

// TestSettler25 is the finding measured on real art rather than on a fixture
// chosen to show it.
//
// Settler #25 carries 20 palette entries. Keyed on the palette index, all 20
// survive into the text. Keyed on luminance, a ten-step ramp resolves them to
// 9: eleven of the artist's twenty colours stop existing, and the shapes
// between them go with it.
//
// That is the whole argument for Glyphs being the default and Ramp being the
// thing you ask for.
func TestSettler25PaletteBeatsLuminance(t *testing.T) {
	glyphs := settler25().Canvas(Glyphs).Text()
	ramp := settler25().Canvas(Ramp).Text()

	// distinctRunes counts the newline too, so both figures are colours + 1.
	uassert.Equal(t, 21, distinctRunes(glyphs), "every palette entry survives")
	uassert.Equal(t, 10, distinctRunes(ramp), "the ramp resolves 20 colours to 9")
	uassert.True(t, distinctRunes(glyphs) > distinctRunes(ramp), "glyphs strictly finer")
}

// TestSettler25SVGIsOnePathPerColour pins the encoding that keeps a sprite
// small enough for a realm to emit. 20 colours, 20 paths, and 4,532 bytes where
// one rectangle per run cost 20,625.
func TestSettler25SVGIsOnePathPerColour(t *testing.T) {
	doc := settler25().SVG(8).String()
	uassert.Equal(t, 20, strings.Count(doc, "<path"), "one path per palette entry")
	uassert.Equal(t, 0, strings.Count(doc, "<rect"), "no rectangles at all")
	uassert.True(t, len(doc) < 6000, "a 32x32 sprite stays well under 6 KB")
	// Scaling is a viewBox change, so the path data, which is all of the size,
	// is byte-identical at any scale. Only the canvas width and height move,
	// and here that is one digit each between "32" and "256".
	one := settler25().SVG(1).String()
	uassert.Equal(t, paths(one), paths(doc), "path data is identical at any scale")
	uassert.Equal(t, 2, len(doc)-len(one), "only the canvas dimensions grow")
}

// paths returns the document from its first <path> on, which is everything
// scale cannot affect.
func paths(doc string) string {
	i := strings.Index(doc, "<path")
	if i < 0 {
		return ""
	}
	return doc[i:]
}

// TestSettler25TextIsSmallerThanItsPicture is the reason a text target is worth
// having at all, beyond readability: the ASCII form of this NFT is a third of
// the SVG.
func TestSettler25TextIsSmallerThanItsPicture(t *testing.T) {
	text := settler25().Canvas(Glyphs).Text()
	uassert.Equal(t, 1469, len(text), "glyph text size")
	uassert.True(t, len(text) < len(settler25().SVG(8).String()), "text is the cheaper form")
}

// TestSettler25RampConfusesHueForBrightness is the part of the finding that is
// easy to miss: the ramp's collisions are not between near-identical shades.
// Two colours a human would never confuse, an orange hat and a sky-blue tunic,
// come out as the same character, because luminance cannot tell a hue from a
// hue.
func TestSettler25RampConfusesHueForBrightness(t *testing.T) {
	orange := settler25Pal.Color(4) // #f08a2a, the hat
	blue := settler25Pal.Color(16)  // #3f8fd1, the tunic

	uassert.Equal(t, 152, Luminance(orange), "orange hat")
	uassert.Equal(t, 130, Luminance(blue), "sky tunic")
	uassert.NotEqual(t, orange, blue, "they are different colours")
	uassert.Equal(t, rampGlyph(orange), rampGlyph(blue), "and the same ramp glyph")

	// Keyed on the palette index instead, they cannot collide: the indices are
	// different, so the glyphs are.
	uassert.NotEqual(t,
		DefaultGlyphs[4%len(DefaultGlyphs)],
		DefaultGlyphs[16%len(DefaultGlyphs)],
		"glyphs keep them apart")
}

func rampGlyph(c int) rune {
	return DefaultRamp[Luminance(c)*len(DefaultRamp)/256]
}
