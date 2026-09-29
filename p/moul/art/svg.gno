package art

import (
	"strings"

	"gno.land/p/moul/svg/v0"
)

// SVGOpts configures [Canvas.SVG]. The zero value is usable: every field falls
// back to the constant beside it.
type SVGOpts struct {
	CellW, CellH int    // cell size in SVG units; 0 means 8 and 16
	FG, BG       int    // what a cell's Default resolves to; Default stays unset
	Font         string // font-family; "" means a monospace stack
}

// Defaults for [SVGOpts]. 8x16 is the usual terminal cell ratio, so art laid
// out for a terminal keeps its proportions.
const (
	DefaultCellW = 8
	DefaultCellH = 16
	DefaultFont  = "ui-monospace,SFMono-Regular,Menlo,Consolas,monospace"
)

// SVG renders the canvas as an SVG document: background colours as run-length
// rectangles, and one <text> element per non-blank cell, centred in its cell so
// the grid stays aligned whatever the renderer's idea of a monospace advance
// width is.
//
// This is how colour reaches gnoweb. [Canvas.ANSI] cannot: raw ESC bytes are
// stripped by p/nt/markdown/sanitize and are garbage in HTML regardless. An
// SVG carries the same two colours per cell through a medium the web can show,
// which is the whole argument for making the target a parameter.
//
// One element per cell rather than one per run is deliberate: a run of text
// would have to assume the font's advance width, and a renderer that disagreed
// would shear the picture. Dense pixel art should go through [Pix.SVG] instead,
// which is run-length and has no font to get wrong.
func (c Canvas) SVG(o SVGOpts) *svg.Canvas {
	cw, ch := o.CellW, o.CellH
	if cw <= 0 {
		cw = DefaultCellW
	}
	if ch <= 0 {
		ch = DefaultCellH
	}
	font := o.Font
	if font == "" {
		font = DefaultFont
	}

	out := svg.NewCanvas(c.W*cw, c.H*ch)
	out.WithViewBox(0, 0, c.W*cw, c.H*ch)
	out.AddStyle("text", "font-family:"+font+";font-size:"+itoa(ch)+"px;text-anchor:middle;dominant-baseline:central")
	out.AddStyle("rect", "shape-rendering:crispEdges")

	// Backgrounds first, as horizontal runs, so they sit under the glyphs.
	for y := 0; y < c.H; y++ {
		x := 0
		for x < c.W {
			bg := c.bgAt(x, y, o.BG)
			run := 1
			for x+run < c.W && c.bgAt(x+run, y, o.BG) == bg {
				run++
			}
			if bg != Default {
				out.Append(svg.NewRectangle(x*cw, y*ch, run*cw, ch, Hex(bg)))
			}
			x += run
		}
	}

	for y := 0; y < c.H; y++ {
		for x := 0; x < c.W; x++ {
			cell := c.Cells[y*c.W+x]
			if cell.R == ' ' || cell.R == 0 {
				continue
			}
			fg := cell.FG
			if fg == Default {
				fg = o.FG
			}
			fill := Hex(fg)
			if fill == "" {
				fill = "currentColor"
			}
			out.Append(svg.NewText(x*cw+cw/2, y*ch+ch/2, escapeXML(string(cell.R)), fill))
		}
	}
	return out
}

func (c Canvas) bgAt(x, y, fallback int) int {
	bg := c.Cells[y*c.W+x].BG
	if bg == Default {
		return fallback
	}
	return bg
}

// escapeXML is here and not in p/moul/svg because svg.Text interpolates its
// content straight into the document: a rune this package can legitimately
// produce, or a title a caller typed, would otherwise close the element.
func escapeXML(s string) string {
	if !strings.ContainsAny(s, "&<>\"") {
		return s
	}
	var b strings.Builder
	for _, r := range s {
		switch r {
		case '&':
			b.WriteString("&amp;")
		case '<':
			b.WriteString("&lt;")
		case '>':
			b.WriteString("&gt;")
		case '"':
			b.WriteString("&quot;")
		default:
			b.WriteRune(r)
		}
	}
	return b.String()
}

func itoa(v int) string {
	if v == 0 {
		return "0"
	}
	neg := v < 0
	if neg {
		v = -v
	}
	var buf [20]byte
	i := len(buf)
	for v > 0 {
		i--
		buf[i] = byte('0' + v%10)
		v /= 10
	}
	if neg {
		i--
		buf[i] = '-'
	}
	return string(buf[i:])
}
