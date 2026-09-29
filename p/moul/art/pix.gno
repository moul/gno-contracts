package art

import (
	"strings"

	"gno.land/p/moul/svg/v0"
)

// Palette maps a pixel's index to a colour, as a hex string ("#e8c39e", "#abc",
// with or without the '#'). An empty entry is transparent: [Pix.SVG] emits no
// rectangle for it and the colour modes give it [Default].
//
// By convention index 0 is the background. [Braille] keys on that convention
// directly, and the default glyph set gives index 0 a space.
type Palette []string

// Color returns the packed colour of a palette index, or [Default] if the index
// is out of range or the entry is empty or unparseable.
func (p Palette) Color(i uint8) int {
	if int(i) >= len(p) {
		return Default
	}
	c, ok := ParseHex(p[i])
	if !ok {
		return Default
	}
	return c
}

// Pix is an indexed bitmap: one palette index per pixel, row-major from the top
// left. This is the shape pixel art actually has on chain, and the reason
// [Glyphs] beats [Ramp] for it.
type Pix struct {
	W, H int
	Idx  []uint8
	Pal  Palette
}

// NewPix returns a w by h bitmap with every pixel at index 0.
func NewPix(w, h int, pal Palette) *Pix {
	if w < 0 {
		w = 0
	}
	if h < 0 {
		h = 0
	}
	return &Pix{W: w, H: h, Idx: make([]uint8, w*h), Pal: pal}
}

// At returns the palette index at (x, y), or 0 off the bitmap. Off-bitmap
// reading as background is what lets the conversions below run past the edge of
// an odd-sized image without a bounds check at every pixel.
func (p *Pix) At(x, y int) uint8 {
	if x < 0 || y < 0 || x >= p.W || y >= p.H {
		return 0
	}
	return p.Idx[y*p.W+x]
}

// Set writes a palette index, clipping silently off the bitmap.
func (p *Pix) Set(x, y int, i uint8) {
	if x < 0 || y < 0 || x >= p.W || y >= p.H {
		return
	}
	p.Idx[y*p.W+x] = i
}

// Color returns the packed colour at (x, y).
func (p *Pix) Color(x, y int) int { return p.Pal.Color(p.At(x, y)) }

// Mode is how a [Pix] becomes a [Canvas]. They are not cosmetic variants of
// each other: they trade resolution, colour and consumer against one another,
// and the package doc says which to reach for.
type Mode int

const (
	// Glyphs gives every palette index its own rune. The right default for
	// sprites and anything else with a small indexed palette.
	Glyphs Mode = iota

	// Ramp picks a rune by luminance. Right for a photograph, wrong for a
	// sprite, and the package doc has the measurement.
	Ramp

	// HalfBlock packs two vertical pixels into one cell with '▀', foreground
	// for the top pixel and background for the bottom. Full colour, square
	// aspect, half the rows. The best-looking mode, and terminal-only.
	HalfBlock

	// Quadrant packs a 2x2 block into one cell. Twice HalfBlock's density,
	// but a cell carries only two colours, so a four-colour block loses two.
	Quadrant

	// Braille packs a 2x4 block into one Braille cell. The densest mode and
	// the only monochrome one: a pixel is on if its index is not 0.
	Braille
)

// DefaultGlyphs is one visually distinct rune per palette index, ordered so
// that neighbouring indices stay apart on screen. Index 0 is a space, matching
// the background convention.
//
// A palette longer than this wraps, which is a real collision: pass your own
// set through [Opts] when that matters.
var DefaultGlyphs = []rune{' ', '#', '@', '%', '*', '+', '=', '~', '-', ':', '.', 'o', 'O', 'x', 'X', 'w', 'W', 'm', 'M', '8'}

// DefaultRamp runs darkest to lightest, for a terminal with a dark background.
// Invert it for a light one.
var DefaultRamp = []rune{' ', '.', ':', '-', '=', '+', '*', '#', '%', '@'}

// Quadrants is indexed by a 4-bit mask: bit 0 top-left, 1 top-right, 2
// bottom-left, 3 bottom-right.
var Quadrants = []rune{' ', '▘', '▝', '▀', '▖', '▌', '▞', '▛', '▗', '▚', '▐', '▜', '▄', '▙', '▟', '█'}

// Opts is the full form of [Pix.Canvas], for callers who want to override a
// mode's defaults.
type Opts struct {
	Mode Mode

	// Glyphs overrides [DefaultGlyphs] for [Glyphs] and [DefaultRamp] for
	// [Ramp]. Ignored by the block modes.
	Glyphs []rune

	// Color carries palette colours into the canvas. The block modes need it
	// and set it by default; the glyph modes default to off, because their
	// whole job is to be readable without colour.
	Color bool

	// Wide emits each pixel as two cells side by side. A terminal cell is
	// about twice as tall as it is wide, so a sprite rendered one cell per
	// pixel comes out squashed to half height. On by default for the glyph
	// modes; meaningless for the block modes, which correct aspect by packing.
	Wide bool
}

// Canvas converts the bitmap using a mode's defaults: [Glyphs] and [Ramp] come
// out wide and monochrome, the block modes come out coloured.
func (p *Pix) Canvas(m Mode) *Canvas {
	o := Opts{Mode: m}
	switch m {
	case Glyphs, Ramp:
		o.Wide = true
	default:
		o.Color = true
	}
	return p.CanvasOpts(o)
}

// CanvasOpts converts the bitmap with the options spelled out.
func (p *Pix) CanvasOpts(o Opts) *Canvas {
	switch o.Mode {
	case HalfBlock:
		return p.halfBlock(o)
	case Quadrant:
		return p.quadrant(o)
	case Braille:
		return p.braille(o)
	case Ramp:
		return p.glyphGrid(o, pickRamp(o.Glyphs))
	default:
		return p.glyphGrid(o, pickGlyphs(o.Glyphs))
	}
}

func pickGlyphs(g []rune) []rune {
	if len(g) == 0 {
		return DefaultGlyphs
	}
	return g
}

func pickRamp(g []rune) []rune {
	if len(g) == 0 {
		return DefaultRamp
	}
	return g
}

// glyphGrid covers both Glyphs and Ramp: they differ only in what they key the
// rune lookup on, which is exactly the finding the package doc records.
func (p *Pix) glyphGrid(o Opts, set []rune) *Canvas {
	step := 1
	if o.Wide {
		step = 2
	}
	out := NewCanvas(p.W*step, p.H)
	for y := 0; y < p.H; y++ {
		for x := 0; x < p.W; x++ {
			idx := p.At(x, y)
			col := p.Pal.Color(idx)

			var r rune
			if o.Mode == Ramp {
				r = set[Luminance(col)*len(set)/256]
			} else {
				r = set[int(idx)%len(set)]
			}

			cell := Cell{R: r, FG: Default, BG: Default}
			if o.Color {
				cell.FG = col
			}
			for k := 0; k < step; k++ {
				out.Set(x*step+k, y, cell)
			}
		}
	}
	return out
}

func (p *Pix) halfBlock(o Opts) *Canvas {
	out := NewCanvas(p.W, (p.H+1)/2)
	for y := 0; y < out.H; y++ {
		for x := 0; x < p.W; x++ {
			top := p.Color(x, y*2)
			bot := Default
			if y*2+1 < p.H {
				bot = p.Color(x, y*2+1)
			}
			if !o.Color {
				// Without colour the upper half block says nothing, so fall
				// back to "is there ink here": full, half, or empty.
				out.Set(x, y, Cell{R: monoHalf(p.At(x, y*2), p.At(x, y*2+1)), FG: Default, BG: Default})
				continue
			}
			out.Set(x, y, Cell{R: '▀', FG: top, BG: bot})
		}
	}
	return out
}

func monoHalf(top, bot uint8) rune {
	switch {
	case top != 0 && bot != 0:
		return '█'
	case top != 0:
		return '▀'
	case bot != 0:
		return '▄'
	}
	return ' '
}

func (p *Pix) quadrant(o Opts) *Canvas {
	out := NewCanvas((p.W+1)/2, (p.H+1)/2)
	for y := 0; y < out.H; y++ {
		for x := 0; x < out.W; x++ {
			var idx [4]uint8
			idx[0] = p.At(x*2, y*2)
			idx[1] = p.At(x*2+1, y*2)
			idx[2] = p.At(x*2, y*2+1)
			idx[3] = p.At(x*2+1, y*2+1)

			if !o.Color {
				mask := 0
				for k := 0; k < 4; k++ {
					if idx[k] != 0 {
						mask |= 1 << uint(k)
					}
				}
				out.Set(x, y, Cell{R: Quadrants[mask], FG: Default, BG: Default})
				continue
			}

			bgIdx, fgIdx, split := twoWaySplit(idx)
			mask := 0
			if split {
				for k := 0; k < 4; k++ {
					if idx[k] == fgIdx {
						mask |= 1 << uint(k)
					}
				}
			}
			fg := Default
			if split {
				fg = p.Pal.Color(fgIdx)
			}
			out.Set(x, y, Cell{R: Quadrants[mask], FG: fg, BG: p.Pal.Color(bgIdx)})
		}
	}
	return out
}

// twoWaySplit picks the two palette indices a 2x2 block is drawn with: the most
// common becomes the background, the most common of the rest the foreground.
// It reports false when every pixel agrees, in which case there is no
// foreground and the cell is a solid background.
//
// A tie goes to the LOWER palette index, which is what makes index 0 behave as
// the background the package documents it to be. Tie-breaking on pixel order
// instead put the ink in the background half the time: a two-colour block split
// down the middle came out as the mirror image of itself, because whichever
// side happened to be scanned first won.
func twoWaySplit(idx [4]uint8) (bg, fg uint8, split bool) {
	bg = mostCommon(idx, false, 0)
	fg = mostCommon(idx, true, bg)
	if fg == bg {
		return bg, bg, false
	}
	return bg, fg, true
}

func mostCommon(idx [4]uint8, skip bool, skipped uint8) uint8 {
	best, bestN := uint8(0), 0
	for k := 0; k < 4; k++ {
		if skip && idx[k] == skipped {
			continue
		}
		n := 0
		for j := 0; j < 4; j++ {
			if idx[j] == idx[k] {
				n++
			}
		}
		if n > bestN || (n == bestN && bestN > 0 && idx[k] < best) {
			best, bestN = idx[k], n
		}
	}
	if bestN == 0 {
		return skipped
	}
	return best
}

// brailleBits maps (col, row) inside a 2x4 block to its bit in U+2800. The
// layout is not sequential: the fourth row was added to the standard late and
// took the two high bits.
var brailleBits = [2][4]uint{
	{0, 1, 2, 6},
	{3, 4, 5, 7},
}

func (p *Pix) braille(o Opts) *Canvas {
	out := NewCanvas((p.W+1)/2, (p.H+3)/4)
	for y := 0; y < out.H; y++ {
		for x := 0; x < out.W; x++ {
			bits := 0
			fg := Default
			for col := 0; col < 2; col++ {
				for row := 0; row < 4; row++ {
					if p.At(x*2+col, y*4+row) == 0 {
						continue
					}
					bits |= 1 << brailleBits[col][row]
					if o.Color && fg == Default {
						fg = p.Color(x*2+col, y*4+row)
					}
				}
			}
			out.Set(x, y, Cell{R: rune(0x2800 + bits), FG: fg, BG: Default})
		}
	}
	return out
}

// SVG renders the bitmap as one <path> per palette colour, each path a
// run-length chain of "M<x> <y>h<w>v1h-<w>z" pixel runs. Transparent palette
// entries emit nothing.
//
// The path lives in pixel coordinates and scale goes on the canvas as a viewBox,
// so scaling up costs no extra bytes at all.
//
// One path per colour rather than one <rect> per run is worth the loop:
// measured on Settler #25 (32x32, 20 colours, read from mainnet 2026-09-29),
// rectangles came to 20,625 bytes against 3,565 for paths, 5.8x. A realm pays
// for those bytes in gas and the reader pays for them in page weight, and the
// settlers realm itself emits paths for the same reason.
//
// Use Canvas.Render or Canvas.String from p/moul/svg to get the markdown image
// or the raw document.
func (p *Pix) SVG(scale int) *svg.Canvas {
	if scale < 1 {
		scale = 1
	}
	out := svg.NewCanvas(p.W*scale, p.H*scale)
	out.WithViewBox(0, 0, p.W, p.H)
	out.AddStyle("path", "shape-rendering:crispEdges")

	for i := 0; i < len(p.Pal); i++ {
		hex := p.Pal.hex(uint8(i))
		if hex == "" {
			continue
		}
		var d strings.Builder
		for y := 0; y < p.H; y++ {
			x := 0
			for x < p.W {
				if p.At(x, y) != uint8(i) {
					x++
					continue
				}
				run := 1
				for x+run < p.W && p.At(x+run, y) == uint8(i) {
					run++
				}
				d.WriteByte('M')
				d.WriteString(itoa(x))
				d.WriteByte(' ')
				d.WriteString(itoa(y))
				d.WriteByte('h')
				d.WriteString(itoa(run))
				d.WriteString("v1h-")
				d.WriteString(itoa(run))
				d.WriteByte('z')
				x += run
			}
		}
		if d.Len() > 0 {
			out.Append(svg.NewPath(d.String(), hex))
		}
	}
	return out
}

// hex returns a palette entry normalised to "#rrggbb", or "" for a transparent
// or unparseable one. Normalising rather than passing the raw string through is
// what keeps an entry a caller typed out of the SVG document unescaped.
func (p Palette) hex(i uint8) string {
	if int(i) >= len(p) {
		return ""
	}
	c, ok := ParseHex(p[i])
	if !ok {
		return ""
	}
	return Hex(c)
}
