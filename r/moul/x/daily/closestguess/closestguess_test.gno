package closestguess

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
)

// resetGame re-initializes package globals so each test starts clean; init()
// runs only once for the whole test binary.
func resetGame(height int64) {
	current = newRound(1, height)
	entries = nil
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
		got := targetFromHeight(tt.height, 1)
		if got < minTarget || got > maxTarget {
			t.Errorf("%s: targetFromHeight(%d,1)=%d, want in %d..%d", tt.name, tt.height, got, minTarget, maxTarget)
		}
		if again := targetFromHeight(tt.height, 1); again != got {
			t.Errorf("%s: non-deterministic: %d != %d", tt.name, again, got)
		}
	}

	// Different round numbers at the same height should (almost always) mix
	// to different targets, so consecutive rounds don't repeat.
	a := targetFromHeight(100, 1)
	b := targetFromHeight(100, 2)
	if a == b {
		t.Errorf("targetFromHeight(100,1) == targetFromHeight(100,2) == %d, want them to differ", a)
	}
}

func TestDistance(t *testing.T) {
	cases := []struct{ a, b, want int }{
		{5, 5, 0},
		{5, 8, 3},
		{8, 5, 3},
		{0, 1000, 1000},
	}
	for _, c := range cases {
		if got := distance(c.a, c.b); got != c.want {
			t.Errorf("distance(%d,%d) = %d, want %d", c.a, c.b, got, c.want)
		}
	}
}

// TestGuessRejectsOutOfRangeAndDuplicate exercises the crossing Guess
// function, so it takes cur realm and calls through cross(cur). A panic
// raised across the crossing call boundary isn't catchable by a plain
// defer/recover; revive() is the boundary-aware way to assert on it.
func TestGuessRejectsOutOfRangeAndDuplicate(cur realm, t *testing.T) {
	resetGame(10)

	alice := testutils.TestAddress("alice")
	testing.SetRealm(testing.NewUserRealm(alice))
	if r := revive(func() { Guess(cross(cur), 0) }); r == nil {
		t.Error("Guess(0) should panic: out of range")
	}

	testing.SetRealm(testing.NewUserRealm(alice))
	msg := Guess(cross(cur), 500)
	if !strings.Contains(msg, "recorded") {
		t.Errorf("Guess(500) = %q, want it to mention 'recorded'", msg)
	}

	testing.SetRealm(testing.NewUserRealm(alice))
	if r := revive(func() { Guess(cross(cur), 501) }); r == nil {
		t.Error("second Guess from the same address should panic")
	}
}

// TestRevealPicksClosestAndStartsNewRound exercises Guess + Reveal together.
func TestRevealPicksClosestAndStartsNewRound(cur realm, t *testing.T) {
	resetGame(50)
	target := current.target
	prevRound := current.number

	alice := testutils.TestAddress("alice")
	bob := testutils.TestAddress("bob")

	far := target + 100
	if far > maxTarget {
		far = target - 100
	}
	if far < minTarget {
		far = minTarget
	}
	near := target + 1
	if near > maxTarget {
		near = target - 1
	}
	if near < minTarget {
		near = minTarget
	}

	testing.SetRealm(testing.NewUserRealm(alice))
	Guess(cross(cur), far)
	testing.SetRealm(testing.NewUserRealm(bob))
	Guess(cross(cur), near)

	msg := Reveal(cross(cur))
	if !strings.Contains(msg, "revealed") {
		t.Errorf("Reveal() = %q, want it to mention 'revealed'", msg)
	}
	if len(leaderboard) != 1 {
		t.Fatalf("leaderboard len = %d, want 1", len(leaderboard))
	}
	if leaderboard[0].winner != bob.String() {
		t.Errorf("winner = %q, want %q (closer guess)", leaderboard[0].winner, bob.String())
	}
	if current.number != prevRound+1 {
		t.Errorf("round number = %d, want %d", current.number, prevRound+1)
	}
	if len(entries) != 0 {
		t.Errorf("entries should reset after Reveal, got %d", len(entries))
	}
}

// TestRevealPanicsWithNoGuesses checks the panic path via revive() (see the
// note on TestGuessRejectsOutOfRangeAndDuplicate).
func TestRevealPanicsWithNoGuesses(cur realm, t *testing.T) {
	resetGame(1)
	if r := revive(func() { Reveal(cross(cur)) }); r == nil {
		t.Error("Reveal() with no guesses should panic")
	}
}

// TestRenderContainsState is a plain read — no cur.
func TestRenderContainsState(t *testing.T) {
	resetGame(3)
	out := Render("")
	for _, want := range []string{"Closest Guess", "Current round", "Leaderboard"} {
		if !strings.Contains(out, want) {
			t.Errorf("Render() missing %q", want)
		}
	}
}
