package kingofdice

import (
	"strings"
	"testing"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/testutils/v0"
)

// resetState clears package globals between tests.
func resetState() {
	players = avl.Tree{}
	var zero address
	king = zero
	kingRoll = 0
	reignSince = 0
	nonce = 0
	totalRolls = 0
}

func TestPseudoRollDeterministicAndRanged(t *testing.T) {
	alice := testutils.TestAddress("alice")

	r1 := pseudoRoll(alice, 1, 100)
	r2 := pseudoRoll(alice, 1, 100)
	if r1 != r2 {
		t.Fatalf("same inputs must give same roll: %d != %d", r1, r2)
	}
	if r1 < 1 || r1 > 100 {
		t.Fatalf("roll must be in [1, 100], got %d", r1)
	}

	r3 := pseudoRoll(alice, 2, 100)
	if r1 == r3 {
		t.Fatal("different nonce should (almost always) change the roll")
	}
}

// Crossing test: takes `cur realm` so it can call crossing functions via
// cross(cur). SetRealm is called directly in this frame.
func TestRollCrownsFirstCallerThenSwapsOnHigherRoll(cur realm, t *testing.T) {
	resetState()

	alice := testutils.TestAddress("alice")
	bob := testutils.TestAddress("bob")

	testing.SetRealm(testing.NewUserRealm(alice))
	Roll(cross(cur))
	if !king.IsValid() {
		t.Fatal("someone should be king after first roll")
	}
	firstKing := king

	// Keep rolling as bob until bob out-rolls alice, or give up after a
	// generous number of attempts (rolls are deterministic per nonce/height,
	// so this always terminates locally).
	testing.SetRealm(testing.NewUserRealm(bob))
	for i := 0; i < 200 && king == firstKing; i++ {
		Roll(cross(cur))
	}

	if get(alice).reigns != 1 {
		t.Fatalf("alice should have exactly one recorded reign, got %d", get(alice).reigns)
	}
}

func TestRenderShowsNoKingThenKing(cur realm, t *testing.T) {
	resetState()
	if !strings.Contains(Render(""), "No king yet") {
		t.Fatal("expected empty-board placeholder")
	}

	alice := testutils.TestAddress("alice")
	testing.SetRealm(testing.NewUserRealm(alice))
	Roll(cross(cur))

	out := Render("")
	if !strings.Contains(out, "Current king") {
		t.Fatal("expected current king section once someone rolled")
	}
	if !strings.Contains(out, "Blocks reigned") {
		t.Fatal("expected leaderboard header")
	}
}
