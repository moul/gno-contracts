package numguess

import (
	"strings"
	"testing"

	"gno.land/p/nt/avl/v0"
)

// resetGame re-initializes package globals so each test starts clean; init()
// runs only once for the whole test binary, and t.Run subtests don't reset it.
func resetGame(height int64) {
	current = newRound(1, height)
	attempts = avl.NewTree()
	leaderboard = nil
}

func TestTargetFromHeight(t *testing.T) {
	tests := []struct {
		name   string
		height int64
	}{
		{"zero", 0},
		{"one", 1},
		{"large", 123456},
		{"negative", -42},
	}
	for _, tt := range tests {
		got := targetFromHeight(tt.height)
		if got < 1 || got > 100 {
			t.Errorf("%s: targetFromHeight(%d)=%d, want in 1..100", tt.name, tt.height, got)
		}
		// determinism: same input -> same output
		if again := targetFromHeight(tt.height); again != got {
			t.Errorf("%s: non-deterministic: %d != %d", tt.name, again, got)
		}
	}
}

// TestGuessHigherLowerCorrect exercises the crossing Guess function, so it
// takes cur realm and calls through cross(cur).
func TestGuessHigherLowerCorrect(cur realm, t *testing.T) {
	resetGame(50)
	target := current.target

	low := target - 1
	if low < 1 {
		low = 1
	}
	high := target + 1
	if high > 100 {
		high = 100
	}

	if low != target {
		if got := Guess(cross(cur), low); got != "higher" {
			t.Errorf("Guess(%d) with target %d = %q, want higher", low, target, got)
		}
	}
	if high != target {
		if got := Guess(cross(cur), high); got != "lower" {
			t.Errorf("Guess(%d) with target %d = %q, want lower", high, target, got)
		}
	}

	got := Guess(cross(cur), target)
	if got != "correct" {
		t.Fatalf("Guess(%d) = %q, want correct", target, got)
	}
	if !current.solved {
		t.Error("round should be solved after correct guess")
	}
	if len(leaderboard) != 1 {
		t.Errorf("leaderboard len = %d, want 1", len(leaderboard))
	}
}

// TestNewRoundResets solves a round then verifies NewRound advances the round
// number and clears attempts.
func TestNewRoundResets(cur realm, t *testing.T) {
	resetGame(7)
	target := current.target

	Guess(cross(cur), target) // solve it
	if !current.solved {
		t.Fatal("expected solved round")
	}
	prevRound := current.number

	testing.SkipHeights(11) // change height so the next target can differ
	msg := NewRound(cross(cur))
	if current.number != prevRound+1 {
		t.Errorf("round number = %d, want %d", current.number, prevRound+1)
	}
	if current.solved {
		t.Error("fresh round should not be solved")
	}
	if totalAttempts() != 0 {
		t.Errorf("attempts should reset, got %d", totalAttempts())
	}
	if !strings.Contains(msg, "started") {
		t.Errorf("NewRound message = %q, want it to mention 'started'", msg)
	}
}

// TestRenderContainsState is a plain read — no cur.
func TestRenderContainsState(t *testing.T) {
	resetGame(3)
	out := Render("")
	for _, want := range []string{"Number Guessing Game", "Current round", "Leaderboard"} {
		if !strings.Contains(out, want) {
			t.Errorf("Render() missing %q", want)
		}
	}
}
