package art

import "strings"

// Cell is one character cell: a rune and its two colours. FG and BG are packed
// 0xRRGGBB values, or [Default].
type Cell struct {
	R      rune
	FG, BG int
}

// Canvas is a fixed grid of cells, addressed (x, y) from the top left.
//
// FG and BG are the pen: the colours the drawing helpers ([Write], [HLine],
// [Box] and the rest) apply to every cell they touch. They start at [Default].
// Set them with [Canvas.Pen]; a caller that only wants shapes can ignore them
// entirely.
type Canvas struct {
	W, H   int
	Cells  []Cell
	FG, BG int
}

// Blank is the cell a new canvas is filled with.
var Blank = Cell{R: ' ', FG: Default, BG: Default}

// NewCanvas returns a w by h canvas of blank cells. Negative dimensions are
// treated as zero, so a canvas built from arithmetic that underflowed is empty
// rather than a panic halfway through a Render.
func NewCanvas(w, h int) *Canvas {
	if w < 0 {
		w = 0
	}
	if h < 0 {
		h = 0
	}
	cells := make([]Cell, w*h)
	for i := 0; i < len(cells); i++ {
		cells[i] = Blank
	}
	return &Canvas{W: w, H: h, Cells: cells, FG: Default, BG: Default}
}

// Pen sets the colours the drawing helpers will apply, and returns the canvas
// so calls can be chained.
func (c *Canvas) Pen(fg, bg int) *Canvas {
	c.FG, c.BG = fg, bg
	return c
}

// In reports whether (x, y) is on the canvas. Every helper in this package
// clips silently rather than panicking: art is drawn by arithmetic and a
// one-off-the-edge line is not worth aborting a Render over.
func (c *Canvas) In(x, y int) bool {
	return x >= 0 && y >= 0 && x < c.W && y < c.H
}

// At returns the cell at (x, y), or [Blank] if that is off the canvas.
func (c *Canvas) At(x, y int) Cell {
	if !c.In(x, y) {
		return Blank
	}
	return c.Cells[y*c.W+x]
}

// Set writes a whole cell, colours included, ignoring the pen.
func (c *Canvas) Set(x, y int, cell Cell) {
	if !c.In(x, y) {
		return
	}
	c.Cells[y*c.W+x] = cell
}

// Put writes one rune in the pen's colours.
func (c *Canvas) Put(x, y int, r rune) {
	c.Set(x, y, Cell{R: r, FG: c.FG, BG: c.BG})
}

// Fill sets every cell on the canvas to cell.
func (c *Canvas) Fill(cell Cell) {
	for i := 0; i < len(c.Cells); i++ {
		c.Cells[i] = cell
	}
}

// Write draws s left to right from (x, y) in the pen's colours. It does not
// wrap: anything past the right edge is clipped. A '\n' moves to the next row,
// back at the starting column, which is what makes a multi-line literal blit
// the way it reads in source.
func (c *Canvas) Write(x, y int, s string) {
	cx, cy := x, y
	for _, r := range s {
		if r == '\n' {
			cx, cy = x, cy+1
			continue
		}
		c.Put(cx, cy, r)
		cx++
	}
}

// HLine draws n runes rightwards from (x, y).
func (c *Canvas) HLine(x, y, n int, r rune) {
	for i := 0; i < n; i++ {
		c.Put(x+i, y, r)
	}
}

// VLine draws n runes downwards from (x, y).
func (c *Canvas) VLine(x, y, n int, r rune) {
	for i := 0; i < n; i++ {
		c.Put(x, y+i, r)
	}
}

// Rect fills a w by h area with r.
func (c *Canvas) Rect(x, y, w, h int, r rune) {
	for j := 0; j < h; j++ {
		c.HLine(x, y+j, w, r)
	}
}

// Blit copies src onto c with src's top left at (x, y), colours and all.
// Cells landing off the edge are dropped.
func (c *Canvas) Blit(x, y int, src *Canvas) {
	if src == nil {
		return
	}
	for j := 0; j < src.H; j++ {
		for i := 0; i < src.W; i++ {
			c.Set(x+i, y+j, src.Cells[j*src.W+i])
		}
	}
}

// Text emits the canvas as plain text: runes only, one line per row, trailing
// spaces trimmed. This is the form that belongs inside a triple-backtick fence,
// and the form a caller can pipe.
//
// Colours are dropped, which is the whole point: a consumer asking for text has
// said it cannot show them.
func (c Canvas) Text() string {
	var b strings.Builder
	for y := 0; y < c.H; y++ {
		var line strings.Builder
		for x := 0; x < c.W; x++ {
			line.WriteRune(c.Cells[y*c.W+x].R)
		}
		b.WriteString(strings.TrimRight(line.String(), " "))
		if y < c.H-1 {
			b.WriteString("\n")
		}
	}
	return b.String()
}

// String is [Canvas.Text], so a canvas can be printed directly.
func (c Canvas) String() string { return c.Text() }

// ANSI emits the canvas with SGR truecolour escapes, one reset at the end of
// every coloured row. Trailing spaces are NOT trimmed here: a trailing cell may
// carry a background colour, and trimming it would put a hole in the picture.
//
// This output cannot reach gnoweb. See the package doc.
func (c Canvas) ANSI() string {
	var b strings.Builder
	for y := 0; y < c.H; y++ {
		fg, bg := Default, Default
		for x := 0; x < c.W; x++ {
			cl := c.Cells[y*c.W+x]
			if cl.FG != fg || cl.BG != bg {
				b.WriteString(sgr(cl.FG, cl.BG))
				fg, bg = cl.FG, cl.BG
			}
			b.WriteRune(cl.R)
		}
		if fg != Default || bg != Default {
			b.WriteString(reset)
		}
		if y < c.H-1 {
			b.WriteString("\n")
		}
	}
	return b.String()
}

// Escape is the byte that starts every SGR sequence. Exported so a consumer can
// strip ANSI without hard-coding "\x1b".
const Escape = '\x1b'

const reset = "\x1b[0m"

func sgr(fg, bg int) string {
	var b strings.Builder
	b.WriteString("\x1b[")
	if fg == Default {
		b.WriteString("39")
	} else {
		r, g, bl := Split(fg)
		b.WriteString("38;2;")
		writeInt(&b, r)
		b.WriteByte(';')
		writeInt(&b, g)
		b.WriteByte(';')
		writeInt(&b, bl)
	}
	b.WriteByte(';')
	if bg == Default {
		b.WriteString("49")
	} else {
		r, g, bl := Split(bg)
		b.WriteString("48;2;")
		writeInt(&b, r)
		b.WriteByte(';')
		writeInt(&b, g)
		b.WriteByte(';')
		writeInt(&b, bl)
	}
	b.WriteByte('m')
	return b.String()
}

// writeInt writes a 0-255 value without strconv, which this package would
// otherwise import for three call sites.
func writeInt(b *strings.Builder, v int) {
	if v >= 100 {
		b.WriteByte(byte('0' + v/100))
	}
	if v >= 10 {
		b.WriteByte(byte('0' + (v/10)%10))
	}
	b.WriteByte(byte('0' + v%10))
}
