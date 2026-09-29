package art

// BoxStyle is the six runes a rectangular border needs.
type BoxStyle struct {
	TL, TR, BL, BR rune
	H, V           rune
}

// The border styles worth having. ASCII is the one that survives a consumer
// with no Unicode: everything else here is box-drawing, which is fine in a
// terminal and in a markdown code fence but not in, say, a plain-ASCII log.
var (
	Light  = BoxStyle{TL: '┌', TR: '┐', BL: '└', BR: '┘', H: '─', V: '│'}
	Heavy  = BoxStyle{TL: '┏', TR: '┓', BL: '┗', BR: '┛', H: '━', V: '┃'}
	Double = BoxStyle{TL: '╔', TR: '╗', BL: '╚', BR: '╝', H: '═', V: '║'}
	Round  = BoxStyle{TL: '╭', TR: '╮', BL: '╰', BR: '╯', H: '─', V: '│'}
	ASCII  = BoxStyle{TL: '+', TR: '+', BL: '+', BR: '+', H: '-', V: '|'}
)

// Box draws a w by h border in the pen's colours, leaving the interior
// untouched. w or h under 2 draws nothing: there is no border with no inside.
func (c *Canvas) Box(x, y, w, h int, s BoxStyle) {
	if w < 2 || h < 2 {
		return
	}
	c.HLine(x+1, y, w-2, s.H)
	c.HLine(x+1, y+h-1, w-2, s.H)
	c.VLine(x, y+1, h-2, s.V)
	c.VLine(x+w-1, y+1, h-2, s.V)
	c.Put(x, y, s.TL)
	c.Put(x+w-1, y, s.TR)
	c.Put(x, y+h-1, s.BL)
	c.Put(x+w-1, y+h-1, s.BR)
}

// Frame returns a NEW canvas two cells wider and taller than c, with c blitted
// into the middle and a border around it. A non-empty title is written into the
// top edge starting two cells in, and is truncated rather than allowed to run
// over the corner.
//
// It returns a new canvas rather than growing this one because a Canvas has a
// fixed size by design: every index in this package is computed from W, and a
// resize in place would invalidate any offset a caller was holding.
func (c *Canvas) Frame(title string, s BoxStyle) *Canvas {
	out := NewCanvas(c.W+2, c.H+2)
	out.FG, out.BG = c.FG, c.BG
	out.Box(0, 0, out.W, out.H, s)
	out.Blit(1, 1, c)
	if title != "" {
		// The top edge has W-2 usable cells and the title starts at x=2, so it
		// gets W-4 of them. Anything less than one cell means no room at all.
		room := out.W - 4
		if room > 0 {
			out.Write(2, 0, truncRunes(title, room))
		}
	}
	return out
}

func truncRunes(s string, n int) string {
	i := 0
	for idx := range s {
		if i == n {
			return s[:idx]
		}
		i++
	}
	return s
}
