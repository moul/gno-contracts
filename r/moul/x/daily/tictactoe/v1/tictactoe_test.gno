package tictactoe

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

var (
	alice = testutils.TestAddress("alice")
	bob   = testutils.TestAddress("bob")
	carol = testutils.TestAddress("carol")
)

// TestXWins: alice (X) beats bob (O) on the top row.
func TestXWins(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	id := NewGame(cross(cur), bob)
	uassert.True(t, id >= 1, "expected a game id")

	// alice X -> 0
	testing.SetRealm(testing.NewUserRealm(alice))
	Move(cross(cur), id, 0)
	// bob O -> 3
	testing.SetRealm(testing.NewUserRealm(bob))
	Move(cross(cur), id, 3)
	// alice X -> 1
	testing.SetRealm(testing.NewUserRealm(alice))
	Move(cross(cur), id, 1)
	// bob O -> 4
	testing.SetRealm(testing.NewUserRealm(bob))
	Move(cross(cur), id, 4)
	// alice X -> 2 wins top row
	testing.SetRealm(testing.NewUserRealm(alice))
	Move(cross(cur), id, 2)

	g, err := GetGame(id)
	uassert.NoError(t, err)
	uassert.True(t, g.finished, "game should be finished")
	uassert.Equal(t, markX, g.winner)
	uassert.False(t, g.draw, "should not be a draw")
}

// TestTurnAndTakenGuards: rejects out-of-turn moves, taken cells, and non-players.
func TestTurnAndTakenGuards(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	id := NewGame(cross(cur), bob)

	// bob (O) cannot move first — it's X's turn.
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsWithMessage(t, cur, "not your turn", func() {
		Move(cross(cur), id, 0)
	})

	// alice (X) plays 0.
	testing.SetRealm(testing.NewUserRealm(alice))
	Move(cross(cur), id, 0)

	// alice cannot play twice in a row.
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsWithMessage(t, cur, "not your turn", func() {
		Move(cross(cur), id, 1)
	})

	// bob cannot take an occupied cell.
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsWithMessage(t, cur, "cell already taken", func() {
		Move(cross(cur), id, 0)
	})

	// carol is not a player.
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsWithMessage(t, cur, "caller is not a player in this game", func() {
		Move(cross(cur), id, 5)
	})
}

// TestDraw: fill the board with no winner.
func TestDraw(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	id := NewGame(cross(cur), bob)

	// Sequence yielding a full board with no three-in-a-row:
	// X:0 O:1 X:2 O:4 X:3 O:5 X:7 O:6 X:8
	seq := []struct {
		who  address
		cell int
	}{
		{alice, 0}, {bob, 1}, {alice, 2},
		{bob, 4}, {alice, 3}, {bob, 5},
		{alice, 7}, {bob, 6}, {alice, 8},
	}
	for _, s := range seq {
		testing.SetRealm(testing.NewUserRealm(s.who))
		Move(cross(cur), id, s.cell)
	}

	g, err := GetGame(id)
	uassert.NoError(t, err)
	uassert.True(t, g.finished, "game should be finished")
	uassert.True(t, g.draw, "should be a draw")
	uassert.Equal(t, 0, g.winner)
}
