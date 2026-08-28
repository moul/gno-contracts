// Package pixelcanvas is a shared 16x16 pixel canvas: anyone can paint one
// cell at a time from a fixed 9-colour palette, and the canvas renders in
// gnoweb as a grid of coloured blocks.
//
// The canvas is a flat [Size*Size]int of palette indices held in realm state —
// a fixed-size array rather than a tree, because every cell exists from the
// start and the grid is walked in full on every render. Painting is
// last-write-wins; the realm keeps who painted each cell and a per-address
// tally, so the board doubles as a contribution leaderboard.
//
// A stateful app with nothing reusable to extract, so it ships as a lone realm
// rather than a p/ library + demo pair.
package pixelcanvas

import (
	"sort"
	"strconv"
	"strings"

	"chain"
	"chain/runtime"

	"gno.land/p/nt/avl/v0"
)

// Size is the canvas edge length; the canvas is Size x Size cells.
const Size = 16

// palette maps a colour index to the block rendered for it. Index 0 is the
// blank canvas. Kept parallel to paletteNames.
var palette = []string{"⬜", "🟥", "🟧", "🟨", "🟩", "🟦", "🟪", "🟫", "⬛"}

// paletteNames are the names Paint accepts, in palette order.
var paletteNames = []string{"white", "red", "orange", "yellow", "green", "blue", "purple", "brown", "black"}

// Package-level persistent state.
var (
	cells    [Size * Size]int // palette index per cell, row-major
	painters [Size * Size]string
	tally    = avl.NewTree() // address string -> *int paint count
	strokes  int             // total paints ever
	lastAt   int64           // height of the most recent paint
)

// Paint colours the cell at (x, y) and returns the total number of strokes.
//
// Coordinates are 0-based with (0,0) at the top-left. Colour is a palette name
// ("red", "blue", …) — see Palette. Painting over an existing cell is allowed:
// the canvas is last-write-wins, which is the whole point of a shared board.
func Paint(cur realm, x, y int, colour string) int {
	if !cur.IsCurrent() {
		panic("spoofed realm")
	}
	prev := cur.Previous()
	if !prev.IsUserCall() {
		panic("only an EOA via MsgCall can paint")
	}
	if x < 0 || x >= Size || y < 0 || y >= Size {
		panic("out of bounds: x and y must be in [0," + strconv.Itoa(Size-1) + "]")
	}
	idx := colourIndex(colour)
	if idx < 0 {
		panic("unknown colour " + strconv.Quote(colour) + "; see Palette()")
	}

	addr := prev.Address()
	i := y*Size + x
	cells[i] = idx
	painters[i] = addr.String()
	strokes++
	lastAt = runtime.ChainHeight()
	bump(addr.String())

	chain.Emit("Paint",
		"addr", addr.String(),
		"x", strconv.Itoa(x),
		"y", strconv.Itoa(y),
		"colour", paletteNames[idx],
	)
	return strokes
}

// colourIndex resolves a palette name to its index, or -1.
func colourIndex(name string) int {
	n := strings.ToLower(strings.TrimSpace(name))
	for i, p := range paletteNames {
		if p == n {
			return i
		}
	}
	return -1
}

// bump increments an address's paint tally.
func bump(addr string) {
	// avl/v0's Get returns a single `any`; a miss is a nil interface.
	if v := tally.Get(addr); v != nil {
		c := v.(*int)
		*c++
		return
	}
	one := 1
	tally.Set(addr, &one)
}

// At returns the palette name of the cell at (x, y), or "" when out of bounds.
func At(x, y int) string {
	if x < 0 || x >= Size || y < 0 || y >= Size {
		return ""
	}
	return paletteNames[cells[y*Size+x]]
}

// PainterAt returns the address that last painted (x, y), or "" if untouched.
func PainterAt(x, y int) string {
	if x < 0 || x >= Size || y < 0 || y >= Size {
		return ""
	}
	return painters[y*Size+x]
}

// Strokes returns how many paints the canvas has taken.
func Strokes() int { return strokes }

// Palette returns the accepted colour names, comma-separated.
func Palette() string { return strings.Join(paletteNames, ", ") }

// scorer is one row of the contribution leaderboard.
type scorer struct {
	addr  string
	count int
}

// byCount ranks painters by strokes descending, ties broken on address so the
// board is deterministic.
type byCount []scorer

func (s byCount) Len() int      { return len(s) }
func (s byCount) Swap(i, j int) { s[i], s[j] = s[j], s[i] }
func (s byCount) Less(i, j int) bool {
	if s[i].count != s[j].count {
		return s[i].count > s[j].count
	}
	return s[i].addr < s[j].addr
}

// Render renders the canvas for gnoweb.
//
//	Render("")        / Render("/") -> the canvas, palette and leaderboard
//	Render("/<x>,<y>")              -> who painted that cell, and what colour
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# Pixel Canvas\n\n")
	b.WriteString("A shared ")
	b.WriteString(strconv.Itoa(Size))
	b.WriteString("x")
	b.WriteString(strconv.Itoa(Size))
	b.WriteString(" canvas. Anyone can `Paint(x, y, colour)` — last write wins.\n\n")

	if q := parseArg(path); q != "" {
		return b.String() + renderCell(q)
	}

	b.WriteString(grid())
	b.WriteString("\n**")
	b.WriteString(strconv.Itoa(strokes))
	b.WriteString("** stroke")
	if strokes != 1 {
		b.WriteString("s")
	}
	b.WriteString(" · palette: ")
	b.WriteString(Palette())
	b.WriteString("\n")

	if board := leaderboard(); board != "" {
		b.WriteString("\n## Top painters\n\n")
		b.WriteString(board)
	}
	return b.String()
}

// grid renders the canvas as rows of coloured blocks.
func grid() string {
	var b strings.Builder
	for y := 0; y < Size; y++ {
		for x := 0; x < Size; x++ {
			b.WriteString(palette[cells[y*Size+x]])
		}
		b.WriteString("\n")
	}
	return b.String()
}

// leaderboard renders the top painters, or "" when nobody has painted.
func leaderboard() string {
	scores := []scorer{}
	tally.Iterate("", "", func(k string, v any) bool {
		scores = append(scores, scorer{addr: k, count: *(v.(*int))})
		return false
	})
	if len(scores) == 0 {
		return ""
	}
	sort.Sort(byCount(scores))
	if len(scores) > 5 {
		scores = scores[:5]
	}

	var b strings.Builder
	b.WriteString("| # | address | strokes |\n|---|---|---|\n")
	for i, s := range scores {
		b.WriteString("| ")
		b.WriteString(strconv.Itoa(i + 1))
		b.WriteString(" | `")
		b.WriteString(s.addr)
		b.WriteString("` | ")
		b.WriteString(strconv.Itoa(s.count))
		b.WriteString(" |\n")
	}
	return b.String()
}

// renderCell renders a single "x,y" lookup.
func renderCell(q string) string {
	var b strings.Builder
	x, y, ok := parseCoord(q)
	if !ok {
		b.WriteString("_Expected `x,y` — e.g. `/3,7`._\n")
		return b.String()
	}
	b.WriteString("## Cell (")
	b.WriteString(strconv.Itoa(x))
	b.WriteString(", ")
	b.WriteString(strconv.Itoa(y))
	b.WriteString(")\n\n")
	b.WriteString(palette[cells[y*Size+x]])
	b.WriteString(" **")
	b.WriteString(At(x, y))
	b.WriteString("**\n\n")
	if p := PainterAt(x, y); p != "" {
		b.WriteString("Painted by `")
		b.WriteString(p)
		b.WriteString("`.\n")
	} else {
		b.WriteString("_Never painted._\n")
	}
	return b.String()
}

// parseArg extracts the first path segment.
func parseArg(path string) string {
	s := strings.TrimSpace(path)
	s = strings.TrimPrefix(s, "/")
	if i := strings.IndexByte(s, '/'); i >= 0 {
		s = s[:i]
	}
	return s
}

// parseCoord parses "x,y" and reports whether it is in bounds.
func parseCoord(s string) (int, int, bool) {
	i := strings.IndexByte(s, ',')
	if i < 0 {
		return 0, 0, false
	}
	x, err := strconv.Atoi(strings.TrimSpace(s[:i]))
	if err != nil {
		return 0, 0, false
	}
	y, err2 := strconv.Atoi(strings.TrimSpace(s[i+1:]))
	if err2 != nil {
		return 0, 0, false
	}
	if x < 0 || x >= Size || y < 0 || y >= Size {
		return 0, 0, false
	}
	return x, y, true
}
