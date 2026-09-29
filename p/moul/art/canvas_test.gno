package art

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestNewCanvasIsBlank(t *testing.T) {
	c := NewCanvas(3, 2)
	uassert.Equal(t, 6, len(c.Cells), "cell count")
	uassert.Equal(t, "\n", c.Text(), "two empty rows, both trimmed to nothing")

	// Negative dimensions must not panic partway through a Render.
	empty := NewCanvas(-4, -4)
	uassert.Equal(t, 0, empty.W, "negative width clamps to 0")
	uassert.Equal(t, "", empty.Text(), "empty canvas is the empty string")
}

func TestWriteAndClip(t *testing.T) {
	cases := []struct {
		name string
		x, y int
		in   string
		want string
	}{
		{"fits", 0, 0, "abc", "abc\n\n"},
		{"offset", 1, 1, "xy", "\n xy\n"},
		{"clipped at the right edge", 2, 0, "abcde", "  abc\n\n"},
		{"negative x drops the leading runes", -2, 0, "abcde", "cde\n\n"},
		{"newline returns to the start column", 1, 0, "ab\ncd", " ab\n cd\n"},
		{"off the bottom is dropped entirely", 0, 9, "abc", "\n\n"},
	}
	for _, tc := range cases {
		c := NewCanvas(5, 3)
		c.Write(tc.x, tc.y, tc.in)
		uassert.Equal(t, tc.want, c.Text(), tc.name)
	}
}

func TestTextTrimsTrailingSpaceAndANSIDoesNot(t *testing.T) {
	c := NewCanvas(4, 1)
	c.Pen(Default, 0xff0000)
	c.Put(0, 0, 'x')
	c.Put(3, 0, ' ') // a trailing space that carries a background colour

	uassert.Equal(t, "x", c.Text(), "text drops the coloured trailing space")

	ansi := c.ANSI()
	uassert.True(t, strings.HasSuffix(ansi, reset), "a coloured row ends in a reset")
	uassert.True(t, strings.Contains(ansi, "48;2;255;0;0"), "the red background is emitted")
	// Trimming here would punch a hole in the picture, so the cell survives.
	uassert.Equal(t, "x   ", stripSGR(ansi), "all four cells survive in ansi")
}

func TestANSIEmitsOneEscapePerChange(t *testing.T) {
	c := NewCanvas(4, 1)
	c.Pen(0x00ff00, Default)
	c.Write(0, 0, "aa")
	c.Pen(0x0000ff, Default)
	c.Write(2, 0, "bb")

	got := c.ANSI()
	// Two colour changes plus the end-of-row reset, and not one per cell.
	uassert.Equal(t, 3, strings.Count(got, "\x1b["), "escape count")
	uassert.Equal(t, "aabb", stripSGR(got), "the runes survive intact")
}

func TestANSIUncolouredRowHasNoEscapes(t *testing.T) {
	c := NewCanvas(3, 1)
	c.Write(0, 0, "abc")
	uassert.Equal(t, "abc", c.ANSI(), "no colour means no escapes and no reset")
}

func TestBlit(t *testing.T) {
	src := NewCanvas(2, 2)
	src.Write(0, 0, "ab\ncd")

	dst := NewCanvas(4, 4)
	dst.Blit(1, 1, src)
	uassert.Equal(t, "\n ab\n cd\n", dst.Text(), "placed at the offset")

	// Partly off the edge keeps what fits and drops the rest.
	edge := NewCanvas(4, 4)
	edge.Blit(3, 3, src)
	uassert.Equal(t, "\n\n\n   a", edge.Text(), "only the top-left cell lands")

	// A nil source is a no-op rather than a panic.
	edge.Blit(0, 0, nil)
}

func TestBoxAndFrame(t *testing.T) {
	c := NewCanvas(5, 3)
	c.Box(0, 0, 5, 3, ASCII)
	uassert.Equal(t, "+---+\n|   |\n+---+", c.Text(), "ascii border")

	// Degenerate boxes draw nothing: there is no border with no inside.
	small := NewCanvas(5, 3)
	small.Box(0, 0, 1, 3, Light)
	small.Box(0, 0, 5, 1, Light)
	uassert.Equal(t, "\n\n", small.Text(), "width or height under 2 draws nothing")

	inner := NewCanvas(3, 1)
	inner.Write(0, 0, "hey")
	framed := inner.Frame("", ASCII)
	uassert.Equal(t, 5, framed.W, "frame adds two columns")
	uassert.Equal(t, 3, framed.H, "frame adds two rows")
	uassert.Equal(t, "+---+\n|hey|\n+---+", framed.Text(), "content centred inside")
}

func TestFrameTitleIsTruncatedNotOverrun(t *testing.T) {
	inner := NewCanvas(4, 1)
	titled := inner.Frame("settlers", ASCII)
	// 6 columns wide: the corners take 2 and the title starts at x=2, so it
	// gets 2 cells and must not eat the top-right corner.
	uassert.True(t, strings.HasPrefix(titled.Text(), "+-se-+\n"), "truncated, corner survives")

	// A canvas too narrow for any title still frames cleanly.
	tiny := NewCanvas(1, 1)
	uassert.Equal(t, "+-+\n| |\n+-+", tiny.Frame("nope", ASCII).Text(), "no room, no title")
}

// stripSGR removes every SGR sequence, so a test can assert on the runes and on
// the escapes separately instead of pinning one long opaque string.
func stripSGR(s string) string {
	var b strings.Builder
	in := false
	for _, r := range s {
		switch {
		case r == Escape:
			in = true
		case in && r == 'm':
			in = false
		case in:
		default:
			b.WriteRune(r)
		}
	}
	return b.String()
}
