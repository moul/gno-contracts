package rpsmatch

import (
	"testing"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/testutils/v0"
)

func resetState() {
	players = avl.Tree{}
	nonce = 0
	totalRounds = 0
	var zero address
	champion = zero
	championWins = 0
}

// Crossing: Throw mutates realm state, so the test needs `cur realm`.
func TestThrowUpdatesStats(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	testing.SetRealm(testing.NewUserRealm(alice))
	Throw(cross(cur), "rock")

	ps := getOrCreate(alice)
	if ps.RoundsPlayed != 1 {
		t.Fatalf("RoundsPlayed = %d, want 1", ps.RoundsPlayed)
	}
	if totalRounds != 1 {
		t.Fatalf("totalRounds = %d, want 1", totalRounds)
	}
}

func TestMatchCompletes(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	testing.SetRealm(testing.NewUserRealm(alice))

	for i := 0; i < 10; i++ {
		ps := getOrCreate(alice)
		if ps.Active == nil && ps.MatchesPlayed > 0 {
			break
		}
		Throw(cross(cur), "rock")
	}

	ps := getOrCreate(alice)
	if ps.MatchesPlayed == 0 {
		t.Fatal("expected a match to complete within 10 rounds")
	}
	if ps.MatchWins+ps.MatchLosses != ps.MatchesPlayed {
		t.Fatalf("wins+losses (%d) != matchesPlayed (%d)", ps.MatchWins+ps.MatchLosses, ps.MatchesPlayed)
	}
}

// Non-crossing: Render is a plain read.
func TestRenderHome(t *testing.T) {
	resetState()
	out := Render("")
	if out == "" {
		t.Fatal("Render(\"\") should not be empty")
	}
}
