package rpsduel

import (
	"testing"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/testutils/v0"
)

func resetState() {
	duels = avl.Tree{}
	players = avl.Tree{}
	nextID = 0
	totalResolved = 0
	var zero address
	champion = zero
	championWins = 0
}

func TestParseMove(t *testing.T) {
	for _, s := range []string{"rock", "Rock", " r ", "paper", "P", "scissors", "S"} {
		if _, ok := parseMove(s); !ok {
			t.Fatalf("parseMove(%q) should be valid", s)
		}
	}
	if _, ok := parseMove("lizard"); ok {
		t.Fatal(`parseMove("lizard") should be invalid`)
	}
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

func TestComputeCommitDeterministicAndSalted(t *testing.T) {
	a := ComputeCommit("rock", "salt1")
	b := ComputeCommit("rock", "salt1")
	if a != b {
		t.Fatal("ComputeCommit should be deterministic for the same move+salt")
	}
	if a == ComputeCommit("rock", "salt2") {
		t.Fatal("different salts should produce different commits")
	}
	if a == ComputeCommit("paper", "salt1") {
		t.Fatal("different moves should produce different commits")
	}
	if len(a) != 64 {
		t.Fatalf("commit length = %d, want 64 (hex sha256)", len(a))
	}
}

// Crossing: Open/Accept/Reveal mutate realm state, so the test needs `cur realm`.
func TestFullDuelChallengerWins(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	bob := testutils.TestAddress("bob")

	commit := ComputeCommit("paper", "s3cr3t")

	testing.SetRealm(testing.NewUserRealm(alice))
	Open(cross(cur), bob.String(), commit)

	v, ok := duels.Get("1")
	if !ok {
		t.Fatal("expected duel #1 to exist")
	}
	d := v.(*duel)
	if d.Status != statusPending {
		t.Fatalf("Status = %v, want pending", d.Status)
	}

	testing.SetRealm(testing.NewUserRealm(bob))
	Accept(cross(cur), "1", "rock")

	if d.Status != statusAwaitingReveal {
		t.Fatalf("Status = %v, want awaiting reveal", d.Status)
	}

	testing.SetRealm(testing.NewUserRealm(alice))
	Reveal(cross(cur), "1", "paper", "s3cr3t")

	if d.Status != statusResolved {
		t.Fatalf("Status = %v, want resolved", d.Status)
	}
	if d.Result != "challenger" {
		t.Fatalf("Result = %q, want challenger (paper beats rock)", d.Result)
	}
	if d.Winner != alice {
		t.Fatal("expected alice to win")
	}
	if totalResolved != 1 {
		t.Fatalf("totalResolved = %d, want 1", totalResolved)
	}

	aliceStats := getOrCreate(alice)
	if aliceStats.Wins != 1 {
		t.Fatalf("alice.Wins = %d, want 1", aliceStats.Wins)
	}
	bobStats := getOrCreate(bob)
	if bobStats.Losses != 1 {
		t.Fatalf("bob.Losses = %d, want 1", bobStats.Losses)
	}
	if !champion.IsValid() || champion != alice {
		t.Fatal("champion should be alice")
	}
}

func TestRevealMismatchPanics(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	bob := testutils.TestAddress("bob")

	testing.SetRealm(testing.NewUserRealm(alice))
	Open(cross(cur), bob.String(), ComputeCommit("rock", "s3cr3t"))

	testing.SetRealm(testing.NewUserRealm(bob))
	Accept(cross(cur), "1", "scissors")

	testing.SetRealm(testing.NewUserRealm(alice))
	rec := revive(func() { Reveal(cross(cur), "1", "paper", "s3cr3t") })
	if rec == nil {
		t.Fatal("expected panic when revealed move doesn't match the commitment")
	}
}

func TestOnlyOpponentCanAccept(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	bob := testutils.TestAddress("bob")
	mallory := testutils.TestAddress("mallory")

	testing.SetRealm(testing.NewUserRealm(alice))
	Open(cross(cur), bob.String(), ComputeCommit("rock", "s3cr3t"))

	testing.SetRealm(testing.NewUserRealm(mallory))
	rec := revive(func() { Accept(cross(cur), "1", "paper") })
	if rec == nil {
		t.Fatal("expected panic when a non-opponent accepts")
	}
}

func TestClaimForfeitBeforeDeadlinePanics(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	bob := testutils.TestAddress("bob")

	testing.SetRealm(testing.NewUserRealm(alice))
	Open(cross(cur), bob.String(), ComputeCommit("rock", "s3cr3t"))

	testing.SetRealm(testing.NewUserRealm(bob))
	Accept(cross(cur), "1", "paper")

	rec := revive(func() { ClaimForfeit(cross(cur), "1") })
	if rec == nil {
		t.Fatal("expected panic when claiming a forfeit before the reveal window expires")
	}
}

func TestClaimForfeitAfterDeadline(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	bob := testutils.TestAddress("bob")

	testing.SetRealm(testing.NewUserRealm(alice))
	Open(cross(cur), bob.String(), ComputeCommit("rock", "s3cr3t"))

	testing.SetRealm(testing.NewUserRealm(bob))
	Accept(cross(cur), "1", "paper")

	testing.SkipHeights(revealWindow + 1)

	ClaimForfeit(cross(cur), "1")

	v, _ := duels.Get("1")
	d := v.(*duel)
	if d.Status != statusForfeited {
		t.Fatalf("Status = %v, want forfeited", d.Status)
	}
	if d.Winner != bob {
		t.Fatal("expected bob to win by forfeit")
	}

	aliceStats := getOrCreate(alice)
	if aliceStats.Forfeits != 1 {
		t.Fatalf("alice.Forfeits = %d, want 1", aliceStats.Forfeits)
	}
}

func TestCancel(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	bob := testutils.TestAddress("bob")

	testing.SetRealm(testing.NewUserRealm(alice))
	Open(cross(cur), bob.String(), ComputeCommit("rock", "s3cr3t"))
	Cancel(cross(cur), "1")

	v, _ := duels.Get("1")
	d := v.(*duel)
	if d.Status != statusCancelled {
		t.Fatalf("Status = %v, want cancelled", d.Status)
	}
}

func TestOpenSelfRejected(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	testing.SetRealm(testing.NewUserRealm(alice))

	rec := revive(func() { Open(cross(cur), alice.String(), ComputeCommit("rock", "s3cr3t")) })
	if rec == nil {
		t.Fatal("expected panic when challenging yourself")
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
