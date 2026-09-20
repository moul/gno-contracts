package tictactoe

import (
	"strconv"
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// emptyRow is one rendered board row with no marks. The trailing space after
// the final pipe is part of renderBoard's output — keep it.
const emptyRow = "| · | · | · | \n"

// TestRenderGame pins the exact single-game view. The game id is taken from
// NewGame rather than hardcoded: realm globals persist across tests, so the
// id depends on how many games earlier tests created.
func TestRenderGame(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	id := NewGame(cross(cur), bob)

	want := "# Tic-Tac-Toe — Game #" + strconv.Itoa(id) + "\n\n" +
		"- X: `" + alice.String() + "`\n" +
		"- O: `" + bob.String() + "`\n\n" +
		emptyRow + emptyRow + emptyRow +
		"\n**Turn: X**\n\n" +
		"Cell indices:\n\n" +
		"| 0 | 1 | 2 |\n| 3 | 4 | 5 |\n| 6 | 7 | 8 |\n"

	uassert.Equal(t, want, Render("/"+strconv.Itoa(id)))
}

// TestRenderReflectsMoves checks the board and status track game state.
func TestRenderReflectsMoves(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	id := NewGame(cross(cur), bob)
	path := "/" + strconv.Itoa(id)

	testing.SetRealm(testing.NewUserRealm(alice))
	Move(cross(cur), id, 0)

	out := Render(path)
	uassert.True(t, strings.Contains(out, "| X | · | · | \n"), "X should appear in cell 0")
	uassert.True(t, strings.Contains(out, "**Turn: O**"), "turn should pass to O")

	testing.SetRealm(testing.NewUserRealm(bob))
	Move(cross(cur), id, 4)
	out = Render(path)
	uassert.True(t, strings.Contains(out, "| X | · | · | \n| · | O | · | \n"), "O should appear in cell 4, below X")
	uassert.True(t, strings.Contains(out, "**Turn: X**"), "turn should pass back to X")
}

// TestRenderFinishedStatus checks a decided game reports its winner.
func TestRenderFinishedStatus(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	id := NewGame(cross(cur), bob)

	// X takes the top row.
	seq := []struct {
		who  address
		cell int
	}{{alice, 0}, {bob, 3}, {alice, 1}, {bob, 4}, {alice, 2}}
	for _, s := range seq {
		testing.SetRealm(testing.NewUserRealm(s.who))
		Move(cross(cur), id, s.cell)
	}

	uassert.True(t, strings.Contains(Render("/"+strconv.Itoa(id)), "**Winner: X**"), "should report X as winner")
}

// TestRenderBadPaths covers the two error branches of Render.
func TestRenderBadPaths(cur realm, t *testing.T) {
	uassert.Equal(t, "# Tic-Tac-Toe\n\nInvalid game id: abc\n", Render("/abc"))
	uassert.Equal(t, "# Tic-Tac-Toe\n\nGame 999999 not found.\n", Render("/999999"))
}

// TestRenderList checks the index lists games created in this run.
func TestRenderList(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	id := NewGame(cross(cur), bob)

	out := Render("")
	uassert.True(t, strings.HasPrefix(out, "# Tic-Tac-Toe\n"), "expected the index header")
	uassert.True(t, strings.Contains(out, "| # | X | O | Status |"), "expected the table header")
	uassert.True(t, strings.Contains(out, "| "+strconv.Itoa(id)+" | `"+alice.String()+"`"), "expected the new game listed")
}
