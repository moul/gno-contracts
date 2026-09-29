package art

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// sprite builds a small indexed bitmap from a rune-per-pixel literal, so a test
// can show the input instead of listing indices.
func sprite(pal Palette, rows ...string) *Pix {
	w := 0
	for _, r := range rows {
		if n := len([]rune(r)); n > w {
			w = n
		}
	}
	p := NewPix(w, len(rows), pal)
	for y, row := range rows {
		for x, r := range []rune(row) {
			if r == '.' {
				continue
			}
			p.Set(x, y, uint8(r-'0'))
		}
	}
	return p
}

// TestRampCollapsesWhatGlyphsKeepsApart is the finding the whole package turns
// on: a luminance ramp is the wrong conversion for indexed art.
//
// Sand (#e8dcc8) and bone (#d9d9d9) are two distinct palette entries any sprite
// might carry. Their luminances are 221 and 217, four steps apart out of 255,
// so a ten-step ramp drops both into bucket 8 and the shape between them
// disappears. Keying on the palette index instead cannot do that, because the
// index IS the artist's own segmentation.
func TestRampCollapsesWhatGlyphsKeepsApart(t *testing.T) {
	pal := Palette{"#000000", "#e8dcc8", "#d9d9d9"}
	uassert.Equal(t, 221, Luminance(0xe8dcc8), "sand")
	uassert.Equal(t, 217, Luminance(0xd9d9d9), "bone")

	p := sprite(pal, "0112")

	ramp := p.CanvasOpts(Opts{Mode: Ramp}).Text()
	glyph := p.CanvasOpts(Opts{Mode: Glyphs}).Text()

	// Both non-background entries land on the same ramp rune, so the two
	// regions merge into one blob.
	uassert.Equal(t, " %%%", ramp, "ramp merges sand and bone")
	uassert.Equal(t, 2, distinctRunes(ramp), "ramp shows two distinct runes")

	// Glyphs keeps three, one per palette index.
	uassert.Equal(t, " ##@", glyph, "glyphs keep every index apart")
	uassert.Equal(t, 3, distinctRunes(glyph), "glyphs show three distinct runes")
}

func TestGlyphDefaultsAreWideAndMonochrome(t *testing.T) {
	p := sprite(Palette{"", "#ff0000"}, "01")

	// A terminal cell is about twice as tall as it is wide, so one cell per
	// pixel would squash a sprite to half height.
	wide := p.Canvas(Glyphs)
	uassert.Equal(t, 4, wide.W, "default doubles the width")
	uassert.Equal(t, "  ##", wide.Text(), "each pixel is two cells")
	uassert.Equal(t, Default, wide.At(2, 0).FG, "no colour by default")

	narrow := p.CanvasOpts(Opts{Mode: Glyphs, Color: true})
	uassert.Equal(t, 2, narrow.W, "Wide off means one cell per pixel")
	uassert.Equal(t, 0xff0000, narrow.At(1, 0).FG, "Color on carries the palette through")
}

func TestCustomGlyphsAndWrapping(t *testing.T) {
	p := sprite(Palette{"", "", ""}, "012")
	got := p.CanvasOpts(Opts{Mode: Glyphs, Glyphs: []rune{'a', 'b'}}).Text()
	// Two glyphs for three indices: index 2 wraps back onto 'a'. A real
	// collision, which is why the doc tells you to pass your own set.
	uassert.Equal(t, "aba", got, "a short glyph set wraps")
}

func TestHalfBlock(t *testing.T) {
	pal := Palette{"", "#ff0000", "#0000ff"}
	p := sprite(pal, "11", "22", "11")

	c := p.Canvas(HalfBlock)
	uassert.Equal(t, 2, c.W, "width is unchanged")
	uassert.Equal(t, 2, c.H, "three rows pack into two cells")

	top := c.At(0, 0)
	uassert.Equal(t, '▀', top.R, "upper half block")
	uassert.Equal(t, 0xff0000, top.FG, "foreground is the top pixel")
	uassert.Equal(t, 0x0000ff, top.BG, "background is the bottom pixel")

	// The odd last row has no partner, so its background falls to Default
	// rather than reading a pixel that is not there.
	uassert.Equal(t, Default, c.At(0, 1).BG, "odd height leaves the last background unset")
}

func TestHalfBlockMonochromeFallsBackToInk(t *testing.T) {
	p := sprite(Palette{"", "#ffffff"}, "10", "01")
	// Without colour, '▀' everywhere would say nothing at all, so the mode
	// reports which halves carry ink instead.
	uassert.Equal(t, "▀▄", p.CanvasOpts(Opts{Mode: HalfBlock}).Text(), "ink map")
}

func TestQuadrant(t *testing.T) {
	pal := Palette{"#000000", "#ff0000"}

	// A solid 2x2 block of one index has no foreground at all.
	solid := sprite(pal, "11", "11").Canvas(Quadrant)
	uassert.Equal(t, ' ', solid.At(0, 0).R, "one colour means a blank cell on a solid background")
	uassert.Equal(t, 0xff0000, solid.At(0, 0).BG, "and that colour is the background")
	uassert.Equal(t, Default, solid.At(0, 0).FG, "with no foreground")

	// Three background pixels and one foreground: the minority becomes the
	// glyph. Bit 0 is top-left.
	corner := sprite(pal, "10", "00").Canvas(Quadrant)
	uassert.Equal(t, '▘', corner.At(0, 0).R, "top-left quadrant")
	uassert.Equal(t, 0xff0000, corner.At(0, 0).FG, "the minority index is the foreground")

	left := sprite(pal, "10", "10").Canvas(Quadrant)
	uassert.Equal(t, '▌', left.At(0, 0).R, "left half")
}

func TestQuadrantPacksFourToOne(t *testing.T) {
	p := sprite(Palette{"", "#fff"}, "1111", "1111", "1111", "1111")
	c := p.Canvas(Quadrant)
	uassert.Equal(t, 2, c.W, "half the columns")
	uassert.Equal(t, 2, c.H, "half the rows")
}

func TestBraille(t *testing.T) {
	p := sprite(Palette{"", "#ffffff"}, "10", "00", "00", "00")
	c := p.Canvas(Braille)
	uassert.Equal(t, 1, c.W, "2 columns pack into 1")
	uassert.Equal(t, 1, c.H, "4 rows pack into 1")
	uassert.Equal(t, rune(0x2801), c.At(0, 0).R, "top-left dot is bit 0")

	// The fourth row took the high bits when it was added to the standard,
	// which is the one thing about Braille that is not sequential.
	low := sprite(Palette{"", "#ffffff"}, "00", "00", "00", "10").Canvas(Braille)
	uassert.Equal(t, rune(0x2840), low.At(0, 0).R, "bottom-left dot is bit 6")

	full := sprite(Palette{"", "#ffffff"}, "11", "11", "11", "11").Canvas(Braille)
	uassert.Equal(t, rune(0x28ff), full.At(0, 0).R, "all eight dots")

	empty := sprite(Palette{"", "#ffffff"}, "00").Canvas(Braille)
	uassert.Equal(t, rune(0x2800), empty.At(0, 0).R, "blank braille, not a space")
}

func TestPixSVGRunLength(t *testing.T) {
	pal := Palette{"", "#ff0000"}
	p := sprite(pal, "0111", "0000")

	doc := p.SVG(4).String()
	// Index 0 is transparent, so it emits nothing; the three red pixels become
	// ONE run in ONE path, not three rectangles.
	uassert.Equal(t, 1, strings.Count(doc, "<path"), "one path per colour")
	uassert.True(t, strings.Contains(doc, `d="M1 0h3v1h-3z"`), "one run, in pixel coordinates")
	uassert.True(t, strings.Contains(doc, `fill="#ff0000"`), "run colour")
	// Scale goes on the canvas, not into the path, so scaling costs no bytes.
	uassert.True(t, strings.Contains(doc, `width="16" height="8"`), "canvas is scaled")
	uassert.True(t, strings.Contains(doc, `viewBox="0 0 4 2"`), "viewBox stays in pixel units")
}

func TestPixSVGNormalisesColour(t *testing.T) {
	// A short-form entry is expanded rather than passed through, which is what
	// keeps an unparseable string a caller typed out of the document.
	p := sprite(Palette{"#abc"}, "0")
	uassert.True(t, strings.Contains(p.SVG(1).String(), `fill="#aabbcc"`), "short form expanded")

	junk := sprite(Palette{`" onload="x`}, "0")
	uassert.Equal(t, 0, strings.Count(junk.SVG(1).String(), "<path"), "an unparseable entry emits nothing")
}

func TestPaletteColorOutOfRange(t *testing.T) {
	pal := Palette{"#000000"}
	uassert.Equal(t, Default, pal.Color(7), "past the end is Default, not a panic")
	uassert.Equal(t, Default, Palette{""}.Color(0), "an empty entry is transparent")
}

func distinctRunes(s string) int {
	var seen []rune
	for _, r := range s {
		found := false
		for _, o := range seen {
			if o == r {
				found = true
				break
			}
		}
		if !found {
			seen = append(seen, r)
		}
	}
	return len(seen)
}
