package leaderboard

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// resetState clears package globals between tests. Global-state reset belongs
// in a helper; realm setup (SetRealm) must NOT — it only affects its own frame.
func resetState() {
	keys := []string{}
	players.Iterate("", "", func(key string, _ any) bool {
		keys = append(keys, key)
		return false
	})
	for _, k := range keys {
		players.Remove(k)
	}
}

const (
	alice = "g1alice00000000000000000000000000000000"
	bob   = "g1bob0000000000000000000000000000000000"
	carol = "g1carol00000000000000000000000000000000"
)

// Crossing test: takes `cur realm` so it can call crossing functions via
// cross(cur). SetRealm is called directly in this frame (never via a helper).
func TestAddPointsAccumulatesAndRanks(cur realm, t *testing.T) {
	resetState()

	testing.SetRealm(testing.NewUserRealm(address(alice)))
	AddPoints(cross(cur), 10)
	AddPoints(cross(cur), 5) // accumulates -> 15

	testing.SetRealm(testing.NewUserRealm(address(bob)))
	AddPoints(cross(cur), 20)

	uassert.Equal(t, 15, get(address(alice)).points, "alice points")
	uassert.Equal(t, 20, get(address(bob)).points, "bob points")

	// Ranking: bob (20) outranks alice (15).
	ranked := snapshot()
	uassert.Equal(t, 2, len(ranked), "player count")
	uassert.Equal(t, bob, ranked[0].addr.String(), "rank 1 is bob")
	uassert.Equal(t, alice, ranked[1].addr.String(), "rank 2 is alice")
}

func TestRenderTableWithMedalsAndName(cur realm, t *testing.T) {
	resetState()

	// Empty board.
	uassert.True(t, strings.Contains(Render(""), "No players yet"), "empty placeholder")

	testing.SetRealm(testing.NewUserRealm(address(alice)))
	AddPoints(cross(cur), 30)
	SetName(cross(cur), "Alice")

	testing.SetRealm(testing.NewUserRealm(address(bob)))
	AddPoints(cross(cur), 20)

	testing.SetRealm(testing.NewUserRealm(address(carol)))
	AddPoints(cross(cur), 10)

	out := Render("")

	uassert.True(t, strings.Contains(out, "| 🥇 | Alice | 30 |"), "Alice gold row")
	uassert.True(t, strings.Contains(out, "🥈"), "silver medal present")
	uassert.True(t, strings.Contains(out, "🥉"), "bronze medal present")
	uassert.True(t, strings.Contains(out, "Total players: **3**"), "total players count")
}

func TestSetNameTooLongPanics(cur realm, t *testing.T) {
	resetState()
	testing.SetRealm(testing.NewUserRealm(address(alice)))
	uassert.AbortsWithMessage(t, cur, "name too long (max 32)", func() {
		SetName(cross(cur), strings.Repeat("x", 33))
	})
}

func TestAddPointsRejectsNonPositive(cur realm, t *testing.T) {
	resetState()
	testing.SetRealm(testing.NewUserRealm(address(alice)))
	uassert.AbortsWithMessage(t, cur, "points must be positive", func() {
		AddPoints(cross(cur), 0)
	})
}
