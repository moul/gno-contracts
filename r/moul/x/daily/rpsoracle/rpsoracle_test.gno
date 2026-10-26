package rpsoracle

import (
	"testing"

	"gno.land/p/moul/x/daily/rps/v0"
	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/testutils/v0"
)

func resetState() {
	players = avl.Tree{}
	nonce = 0
	totalRounds = 0
	oracleCorrect = 0
	var zero address
	topOutwitter = zero
	topOutwitterWins = 0
}

func TestBeats(t *testing.T) {
	if beats(rps.Rock) != rps.Paper {
		t.Fatal("beats(Rock) should be Paper")
	}
	if beats(rps.Paper) != rps.Scissors {
		t.Fatal("beats(Paper) should be Scissors")
	}
	if beats(rps.Scissors) != rps.Rock {
		t.Fatal("beats(Scissors) should be Rock")
	}
}

func TestPredictPicksMostFrequent(t *testing.T) {
	ps := &playerState{}
	ps.Counts[rps.Paper] = 5
	ps.Counts[rps.Rock] = 1
	if got := predict(ps, 0); got != rps.Paper {
		t.Fatalf("predict = %v, want Paper", got)
	}
}

// Crossing: Play mutates realm state, so the test needs `cur realm`.
func TestOracleCountersPredictableRock(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	testing.SetRealm(testing.NewUserRealm(alice))

	for i := 0; i < 5; i++ {
		Play(cross(cur), "rock")
	}
	ps := getOrCreate(alice)
	if ps.Losses == 0 {
		t.Fatal("expected the oracle to eventually counter an all-rock player")
	}
	if ps.Rounds != 5 {
		t.Fatalf("Rounds = %d, want 5", ps.Rounds)
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
