package life

import (
	"strconv"
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// ExampleRender pins the whole page on a deliberately small board so the
// expected output stays readable. initBoard resets the grid, so this example
// is independent of the tests that run before it.
func ExampleRender() {
	initBoard(5, 3)
	SetCell(1, 1, true)
	SetCell(2, 1, true)
	SetCell(3, 1, true)
	print(Render(""))
	// Output:
	// # Conway's Game of Life
	//
	// > A classic cellular automaton, ported to Gno — board state lives on-chain.
	//
	// **Generation:** 0 | **Population:** 3 | **Board:** 5×3
	//
	// ```
	// +-----+
	// |.....|
	// |.OOO.|
	// |.....|
	// +-----+
	// ```
	//
	// ## Transactions
	//
	// | Call | Effect |
	// |---|---|
	// | `Step()` | Advance one generation |
	// | `MultiStep(n)` | Advance *n* generations (max 100) |
	// | `SetCell(x, y, alive)` | Flip a single cell |
	// | `Reset(w, h)` | Clear and resize (max 50×40) |
	// | `LoadPreset(name)` | `glider` · `blinker` · `toad` · `beacon` · `block` · `pulsar` |
	//
	// ## Rules
	//
	// 1. A live cell with 2 or 3 live neighbours survives.
	// 2. A dead cell with exactly 3 live neighbours becomes alive.
	// 3. All other cells die or remain dead.
}

// TestRenderTracksGeneration checks the header counters follow the simulation.
func TestRenderTracksGeneration(t *testing.T) {
	initBoard(5, 3)
	SetCell(1, 1, true)
	SetCell(2, 1, true)
	SetCell(3, 1, true)

	uassert.True(t, strings.Contains(Render(""), "**Generation:** 0 | **Population:** 3"),
		"fresh board should report generation 0")

	Step() // blinker rotates to vertical; on a 3-row board only the centre survives
	out := Render("")
	uassert.True(t, strings.Contains(out, "**Generation:** 1"), "generation should advance")
	uassert.True(t, strings.Contains(out, "**Population:** "+strconv.Itoa(population)),
		"rendered population should match the counter")
}

// TestRenderDrawsLiveCells checks the ASCII grid maps cells to O/. correctly.
func TestRenderDrawsLiveCells(t *testing.T) {
	initBoard(3, 3)
	SetCell(0, 0, true)
	SetCell(2, 2, true)

	out := Render("")
	uassert.True(t, strings.Contains(out, "+---+\n|O..|\n|...|\n|..O|\n+---+"),
		"corners should render as live cells")
}

// TestRenderBoardDimensions checks the border and header follow a resize.
func TestRenderBoardDimensions(t *testing.T) {
	initBoard(8, 2)
	out := Render("")
	uassert.True(t, strings.Contains(out, "**Board:** 8×2"), "header should report the new size")
	uassert.True(t, strings.Contains(out, "+"+strings.Repeat("-", 8)+"+"), "border should match width")
}

// TestRenderIgnoresPath documents that Render has no sub-routes.
func TestRenderIgnoresPath(t *testing.T) {
	initBoard(4, 4)
	uassert.Equal(t, Render(""), Render("/whatever"))
}
