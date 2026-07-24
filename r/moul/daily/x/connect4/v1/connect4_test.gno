package connect4

import (
	"strings"
	"testing"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/testutils"
	"gno.land/p/nt/uassert"
)

var (
	alice = testutils.TestAddress("alice") // 🔴
	bob   = testutils.TestAddress("bob")   // 🟡
	carol = testutils.TestAddress("carol")
)

func resetState() {
	games = avl.NewTree()
	nextID = 0
}

// TestVerticalWin plays 🔴 stacking column 0 four high while 🟡 plays column 1.
func TestVerticalWin(cur realm, t *testing.T) {
	resetState()

	testing.SetRealm(testing.NewUserRealm(alice))
	id := cross(cur).NewGame(bob)
	uassert.Equal(t, int64(1), id)

	for i := 0; i < 3; i++ {
		testing.SetRealm(testing.NewUserRealm(alice))
		cross(cur).Drop(id, 0)
		testing.SetRealm(testing.NewUserRealm(bob))
		cross(cur).Drop(id, 1)
	}
	// alice's 4th disc in column 0 -> vertical win
	testing.SetRealm(testing.NewUserRealm(alice))
	cross(cur).Drop(id, 0)

	g, err := getGame(id)
	uassert.NoError(t, err)
	uassert.True(t, g.Finished)
	uassert.Equal(t, red, g.Winner)

	out := Render("1")
	uassert.True(t, strings.Contains(out, "🔴 Red wins!"))
}

// TestTurnOrderAndErrors covers turn enforcement, non-player, full-column and range checks.
func TestTurnOrderAndErrors(cur realm, t *testing.T) {
	resetState()

	testing.SetRealm(testing.NewUserRealm(alice))
	id := cross(cur).NewGame(bob)

	// bob cannot move first (red starts)
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsWithMessage(t, "not your turn", func() {
		cross(cur).Drop(id, 0)
	})

	// stranger cannot play
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsWithMessage(t, "caller is not a player in this game", func() {
		cross(cur).Drop(id, 0)
	})

	// out-of-range column
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsWithMessage(t, "column out of range (0-6)", func() {
		cross(cur).Drop(id, 7)
	})

	// fill column 3: alice & bob alternate, 6 discs total
	col := 3
	for i := 0; i < 3; i++ {
		testing.SetRealm(testing.NewUserRealm(alice))
		cross(cur).Drop(id, col)
		testing.SetRealm(testing.NewUserRealm(bob))
		cross(cur).Drop(id, col)
	}
	// column now full; whoever is on turn overflows it
	g, _ := getGame(id)
	var mover address
	if g.Turn == red {
		mover = alice
	} else {
		mover = bob
	}
	testing.SetRealm(testing.NewUserRealm(mover))
	uassert.AbortsWithMessage(t, "column is full", func() {
		cross(cur).Drop(id, col)
	})
}

// TestHorizontalWin: 🔴 across columns 0-3 on the bottom row.
func TestHorizontalWin(cur realm, t *testing.T) {
	resetState()

	testing.SetRealm(testing.NewUserRealm(alice))
	id := cross(cur).NewGame(bob)

	// alice drops cols 0,1,2 ; bob answers on row above (col 0,1,2)
	for c := 0; c < 3; c++ {
		testing.SetRealm(testing.NewUserRealm(alice))
		cross(cur).Drop(id, c)
		testing.SetRealm(testing.NewUserRealm(bob))
		cross(cur).Drop(id, c)
	}
	// alice completes col 3 on bottom row -> 0,1,2,3 horizontal
	testing.SetRealm(testing.NewUserRealm(alice))
	cross(cur).Drop(id, 3)

	g, err := getGame(id)
	uassert.NoError(t, err)
	uassert.True(t, g.Finished)
	uassert.Equal(t, red, g.Winner)
}

// TestRenderList checks the listing view renders created games.
func TestRenderList(cur realm, t *testing.T) {
	resetState()

	testing.SetRealm(testing.NewUserRealm(alice))
	cross(cur).NewGame(bob)

	out := Render("")
	uassert.True(t, strings.Contains(out, "Connect Four"))
	uassert.True(t, strings.Contains(out, "to move"))
}
