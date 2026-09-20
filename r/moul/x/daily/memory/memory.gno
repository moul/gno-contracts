// Package memory implements "Memory Match", a concentration game on a
// 4x4 grid of 8 emoji pairs. The board is shuffled deterministically from
// the current block height (no on-chain RNG exists), so a NewGame started at
// a given height always produces the same layout.
package memory

import (
	"strconv"
	"strings"

	"chain"
	"chain/runtime"
)

const gridSize = 16 // 4x4
const numPairs = 8

// faces are the 8 distinct emoji; each appears exactly twice on the board.
var faces = [numPairs]string{"🐶", "🐱", "🦊", "🐸", "🐵", "🐼", "🦁", "🐧"}

// tile holds the face index (0..7) for a cell and whether it is matched.
type tile struct {
	face    int
	matched bool
}

// board is the full game state. It is a package-level singleton so the realm
// persists a single shared game.
var board = struct {
	tiles   [gridSize]tile
	flipped []int // indices currently face-up but not yet resolved (0, 1 or 2)
	moves   int   // number of completed two-tile attempts
	pairs   int   // matched pairs so far
	height  int64 // block height the current game was seeded from
	started bool
}{}

// shuffle produces a deterministic permutation of the 16 tile faces from a
// 64-bit seed. It fills a slice with two of each face index then applies a
// Fisher-Yates shuffle driven by a simple LCG — fully deterministic, no RNG.
func shuffle(seed int64) [gridSize]tile {
	vals := make([]int, 0, gridSize)
	for i := 0; i < numPairs; i++ {
		vals = append(vals, i, i)
	}
	// LCG (Numerical Recipes constants); force unsigned-style math via uint64.
	state := uint64(seed)*6364136223846793005 + 1442695040888963407
	for i := len(vals) - 1; i > 0; i-- {
		state = state*6364136223846793005 + 1442695040888963407
		j := int(state % uint64(i+1))
		vals[i], vals[j] = vals[j], vals[i]
	}
	var out [gridSize]tile
	for i := 0; i < gridSize; i++ {
		out[i] = tile{face: vals[i], matched: false}
	}
	return out
}

func ensureStarted() {
	if !board.started {
		reset(runtime.ChainHeight())
	}
}

func reset(height int64) {
	board.tiles = shuffle(height)
	board.flipped = nil
	board.moves = 0
	board.pairs = 0
	board.height = height
	board.started = true
}

// NewGame reshuffles the board using the current block height as the seed.
func NewGame(cur realm) {
	reset(runtime.ChainHeight())
	chain.Emit("NewGame", "height", strconv.FormatInt(board.height, 10))
}

// Flip reveals the tile at index (0..15).
//
// Rules:
//   - If two tiles are already showing from a previous unmatched attempt,
//     this Flip first clears them (they turn back to hidden), then reveals
//     the requested tile as the first of a new attempt.
//   - Revealing the second tile of an attempt completes a move: matching
//     faces stay face-up (matched); a mismatch leaves both showing until the
//     next Flip clears them.
//   - Flipping an already-matched or already-showing tile is rejected.
func Flip(cur realm, index int) {
	ensureStarted()

	if index < 0 || index >= gridSize {
		panic("index out of range")
	}
	if board.tiles[index].matched {
		panic("tile already matched")
	}

	// A completed unmatched attempt (2 face-up, non-matching) is cleared
	// before the next reveal.
	if len(board.flipped) == 2 {
		board.flipped = nil
	}

	for _, f := range board.flipped {
		if f == index {
			panic("tile already flipped")
		}
	}

	board.flipped = append(board.flipped, index)

	if len(board.flipped) != 2 {
		chain.Emit("Flip", "index", strconv.Itoa(index))
		return
	}

	// Second tile of the attempt: resolve.
	board.moves++
	a, b := board.flipped[0], board.flipped[1]
	if board.tiles[a].face == board.tiles[b].face {
		board.tiles[a].matched = true
		board.tiles[b].matched = true
		board.pairs++
		board.flipped = nil
		chain.Emit("Match", "index", strconv.Itoa(index), "pairs", strconv.Itoa(board.pairs))
	} else {
		// leave both showing; next Flip clears them
		chain.Emit("Miss", "index", strconv.Itoa(index))
	}
}

func solved() bool {
	return board.pairs == numPairs
}

// cellFace returns the emoji to display for a cell given the current state.
func cellFace(i int) string {
	if board.tiles[i].matched {
		return faces[board.tiles[i].face]
	}
	for _, f := range board.flipped {
		if f == i {
			return faces[board.tiles[i].face]
		}
	}
	return "❓"
}

// Render draws the board as Markdown: a 4x4 grid, move count and solved state.
func Render(path string) string {
	ensureStarted()

	var sb strings.Builder
	sb.WriteString("# 🧠 Memory Match\n\n")
	sb.WriteString("Match all 8 emoji pairs on the 4x4 grid.\n\n")

	sb.WriteString("| | | | |\n")
	sb.WriteString("|:-:|:-:|:-:|:-:|\n")
	for row := 0; row < 4; row++ {
		sb.WriteString("|")
		for col := 0; col < 4; col++ {
			sb.WriteString(" " + cellFace(row*4+col) + " |")
		}
		sb.WriteString("\n")
	}

	sb.WriteString("\n")
	sb.WriteString("- Moves: **" + strconv.Itoa(board.moves) + "**\n")
	sb.WriteString("- Pairs matched: **" + strconv.Itoa(board.pairs) + " / " + strconv.Itoa(numPairs) + "**\n")
	sb.WriteString("- Seed height: **" + strconv.FormatInt(board.height, 10) + "**\n\n")

	if solved() {
		sb.WriteString("🎉 **Solved in " + strconv.Itoa(board.moves) + " moves!** Call `NewGame` to play again.\n")
	} else {
		sb.WriteString("Call `Flip(index)` with a cell index 0–15. `NewGame()` reshuffles.\n")
	}

	return sb.String()
}
