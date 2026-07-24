package coinflipduel

import (
	"testing"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/testutils/v0"
)

func resetState() {
	duels = avl.Tree{}
	players = avl.Tree{}
	nextID = 0
	flipNonce = 0
	totalDone = 0
	var zero address
	champion = zero
	championWins = 0
}

func TestParseCall(t *testing.T) {
	for _, s := range []string{"heads", "Heads", " h ", "tails", "T"} {
		if _, ok := parseCall(s); !ok {
			t.Fatalf("parseCall(%q) should be valid", s)
		}
	}
	if _, ok := parseCall("sideways"); ok {
		t.Fatal(`parseCall("sideways") should be invalid`)
	}
}

// Crossing: Challenge and Accept mutate realm state, so the test needs `cur realm`.
func TestChallengeAndAccept(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	bob := testutils.TestAddress("bob")

	testing.SetRealm(testing.NewUserRealm(alice))
	Challenge(cross(cur), bob.String(), "heads")

	if !duels.Has("1") {
		t.Fatal("expected duel #1 to exist")
	}

	testing.SetRealm(testing.NewUserRealm(bob))
	Accept(cross(cur), "1")

	v := duels.Get("1")
	d := v.(*duel)
	if d.Status != statusResolved {
		t.Fatalf("Status = %v, want resolved", d.Status)
	}
	if d.Result != "heads" && d.Result != "tails" {
		t.Fatalf("Result = %q, want heads or tails", d.Result)
	}
	if totalDone != 1 {
		t.Fatalf("totalDone = %d, want 1", totalDone)
	}

	winnerStats := getOrCreate(d.Winner)
	if winnerStats.Wins != 1 {
		t.Fatalf("winner Wins = %d, want 1", winnerStats.Wins)
	}
	if !champion.IsValid() || champion != d.Winner {
		t.Fatal("champion should be the duel winner")
	}
}

func TestChallengeSelfRejected(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	testing.SetRealm(testing.NewUserRealm(alice))

	// Challenge panics inside a cross-realm call; a plain defer/recover in
	// this test does not catch a cross-boundary panic, so use revive().
	rec := revive(func() { Challenge(cross(cur), alice.String(), "heads") })
	if rec == nil {
		t.Fatal("expected panic when challenging yourself")
	}
}

func TestOnlyOpponentCanAccept(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	bob := testutils.TestAddress("bob")
	mallory := testutils.TestAddress("mallory")

	testing.SetRealm(testing.NewUserRealm(alice))
	Challenge(cross(cur), bob.String(), "tails")

	testing.SetRealm(testing.NewUserRealm(mallory))
	rec := revive(func() { Accept(cross(cur), "1") })
	if rec == nil {
		t.Fatal("expected panic when a non-opponent accepts")
	}
}

func TestCancel(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	bob := testutils.TestAddress("bob")

	testing.SetRealm(testing.NewUserRealm(alice))
	Challenge(cross(cur), bob.String(), "heads")
	Cancel(cross(cur), "1")

	v := duels.Get("1")
	d := v.(*duel)
	if d.Status != statusCancelled {
		t.Fatalf("Status = %v, want cancelled", d.Status)
	}
}

// Non-crossing: Render is a plain read.
func TestRenderHome(t *testing.T) {
	resetState()
	out := Render("")
	if out == "" {
		t.Fatal(`Render("") should not be empty`)
	}
}
