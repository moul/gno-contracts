// Conway's Game of Life on Gno — the entire board lives on-chain.
// Anyone can call Step() to tick the simulation forward, load classic
// patterns, or sculpt cells one by one.
package life

import (
	"strconv"
	"strings"
)

const (
	MaxWidth  = 50
	MaxHeight = 40
)

var (
	width      = 20
	height     = 15
	cells      []bool
	generation int
	population int
)

func init() {
	initBoard(width, height)
	LoadPreset("glider")
}

func initBoard(w, h int) {
	if w < 1 {
		w = 1
	}
	if w > MaxWidth {
		w = MaxWidth
	}
	if h < 1 {
		h = 1
	}
	if h > MaxHeight {
		h = MaxHeight
	}
	width = w
	height = h
	cells = make([]bool, width*height)
	generation = 0
	population = 0
}

func cellIdx(x, y int) int {
	return y*width + x
}

func alive(x, y int) bool {
	if x < 0 || x >= width || y < 0 || y >= height {
		return false
	}
	return cells[cellIdx(x, y)]
}

func countNeighbors(x, y int) int {
	n := 0
	for dy := -1; dy <= 1; dy++ {
		for dx := -1; dx <= 1; dx++ {
			if dx == 0 && dy == 0 {
				continue
			}
			if alive(x+dx, y+dy) {
				n++
			}
		}
	}
	return n
}

// Step advances the simulation by exactly one generation.
func Step() {
	next := make([]bool, width*height)
	newPop := 0
	for y := 0; y < height; y++ {
		for x := 0; x < width; x++ {
			n := countNeighbors(x, y)
			var live bool
			if alive(x, y) {
				live = n == 2 || n == 3
			} else {
				live = n == 3
			}
			next[cellIdx(x, y)] = live
			if live {
				newPop++
			}
		}
	}
	cells = next
	population = newPop
	generation++
}

// MultiStep advances the simulation by n generations (capped at 100).
func MultiStep(n int) {
	if n < 1 {
		n = 1
	}
	if n > 100 {
		n = 100
	}
	for i := 0; i < n; i++ {
		Step()
	}
}

// SetCell sets or clears a specific cell.
func SetCell(x, y int, live bool) {
	if x < 0 || x >= width || y < 0 || y >= height {
		return
	}
	i := cellIdx(x, y)
	was := cells[i]
	cells[i] = live
	if live && !was {
		population++
	} else if !live && was {
		population--
	}
}

// Reset clears the board and resizes it to w×h.
func Reset(w, h int) {
	initBoard(w, h)
}

// LoadPreset loads a classic Game of Life pattern onto the current board.
// Names: glider, blinker, toad, beacon, block, pulsar.
func LoadPreset(name string) {
	for i := range cells {
		cells[i] = false
	}
	generation = 0
	population = 0

	cx := width / 2
	cy := height / 2

	switch name {
	case "glider":
		//  .O.
		//  ..O
		//  OOO
		SetCell(1, 0, true)
		SetCell(2, 1, true)
		SetCell(0, 2, true)
		SetCell(1, 2, true)
		SetCell(2, 2, true)

	case "blinker":
		// OOO  (period-2 oscillator)
		SetCell(cx-1, cy, true)
		SetCell(cx, cy, true)
		SetCell(cx+1, cy, true)

	case "toad":
		// period-2 oscillator
		SetCell(cx, cy-1, true)
		SetCell(cx+1, cy-1, true)
		SetCell(cx+2, cy-1, true)
		SetCell(cx-1, cy, true)
		SetCell(cx, cy, true)
		SetCell(cx+1, cy, true)

	case "beacon":
		// period-2 oscillator
		SetCell(cx-2, cy-2, true)
		SetCell(cx-1, cy-2, true)
		SetCell(cx-2, cy-1, true)
		SetCell(cx, cy, true)
		SetCell(cx+1, cy, true)
		SetCell(cx, cy+1, true)
		SetCell(cx+1, cy+1, true)

	case "block":
		// 2×2 still life
		SetCell(cx, cy, true)
		SetCell(cx+1, cy, true)
		SetCell(cx, cy+1, true)
		SetCell(cx+1, cy+1, true)

	case "pulsar":
		// period-3 oscillator (needs at least 17×17 board)
		for _, d := range []int{-4, -3, -2, 2, 3, 4} {
			SetCell(cx+d, cy-6, true)
			SetCell(cx+d, cy-1, true)
			SetCell(cx+d, cy+1, true)
			SetCell(cx+d, cy+6, true)
			SetCell(cx-6, cy+d, true)
			SetCell(cx-1, cy+d, true)
			SetCell(cx+1, cy+d, true)
			SetCell(cx+6, cy+d, true)
		}

	default:
		LoadPreset("glider")
	}
}

// Render returns a Markdown snapshot of the current board.
func Render(path string) string {
	out := "# Conway's Game of Life\n\n"
	out += "> A classic cellular automaton, ported to Gno — board state lives on-chain.\n\n"
	out += "**Generation:** " + strconv.Itoa(generation)
	out += " | **Population:** " + strconv.Itoa(population)
	out += " | **Board:** " + strconv.Itoa(width) + "×" + strconv.Itoa(height) + "\n\n"

	border := "+" + strings.Repeat("-", width) + "+\n"
	out += "```\n"
	out += border
	for y := 0; y < height; y++ {
		row := "|"
		for x := 0; x < width; x++ {
			if alive(x, y) {
				row += "O"
			} else {
				row += "."
			}
		}
		row += "|\n"
		out += row
	}
	out += border
	out += "```\n\n"

	out += "## Transactions\n\n"
	out += "| Call | Effect |\n"
	out += "|---|---|\n"
	out += "| `Step()` | Advance one generation |\n"
	out += "| `MultiStep(n)` | Advance *n* generations (max 100) |\n"
	out += "| `SetCell(x, y, alive)` | Flip a single cell |\n"
	out += "| `Reset(w, h)` | Clear and resize (max " + strconv.Itoa(MaxWidth) + "×" + strconv.Itoa(MaxHeight) + ") |\n"
	out += "| `LoadPreset(name)` | `glider` · `blinker` · `toad` · `beacon` · `block` · `pulsar` |\n\n"

	out += "## Rules\n\n"
	out += "1. A live cell with 2 or 3 live neighbours survives.\n"
	out += "2. A dead cell with exactly 3 live neighbours becomes alive.\n"
	out += "3. All other cells die or remain dead.\n"

	return out
}
