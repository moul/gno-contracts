package rpsoracle

import (
	"testing"

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

func TestJudge(t *testing.T) {
	cases := []struct {
		p, h Move
		want int
	}{
		{Rock, Rock, 0},
		{Paper, Paper, 0},
		{Scissors, Scissors, 0},
		{Paper, Rock, 1},
		{Scissors, Paper, 1},
		{Rock, Scissors, 1},
		{Rock, Paper, 2},
		{Paper, Scissors, 2},
		{Scissors, Rock, 2},
	}
	for _, c := range cases {
		if got := judge(c.p, c.h); got != c.want {
			t.Fatalf("judge(%v,%v) = %d, want %d", c.p, c.h, got, c.want)
		}
	}
}

func TestBeats(t *testing.T) {
	if beats(Rock) != Paper {
		t.Fatal("beats(Rock) should be Paper")
	}
	if beats(Paper) != Scissors {
		t.Fatal("beats(Paper) should be Scissors")
	}
	if beats(Scissors) != Rock {
		t.Fatal("beats(Scissors) should be Rock")
	}
}

func TestParseMove(t *testing.T) {
	for _, s := range []string{"rock", "Rock", " r ", "paper", "P", "scissors", "S"} {
		if _, ok := parseMove(s); !ok {
			t.Fatalf("parseMove(%q) should be valid", s)
		}
	}
	if _, ok := parseMove("lizard"); ok {
		t.Fatal("parseMove(\"lizard\") should be invalid")
	}
}

func TestPredictPicksMostFrequent(t *testing.T) {
	ps := &playerState{}
	ps.Counts[Paper] = 5
	ps.Counts[Rock] = 1
	if got := predict(ps, 0); got != Paper {
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
