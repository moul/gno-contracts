package qvote

import (
	"strings"
	"testing"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/testutils/v0"
)

func resetState() {
	polls = avl.Tree{}
	voters = avl.Tree{}
	nextID = 0
}

func TestSquare(t *testing.T) {
	cases := []struct {
		n, want int64
	}{
		{0, 0}, {1, 1}, {2, 4}, {3, 9}, {10, 100},
	}
	for _, c := range cases {
		if got := square(c.n); got != c.want {
			t.Fatalf("square(%d) = %d, want %d", c.n, got, c.want)
		}
	}
}

// Crossing: CreatePoll mutates realm state, so the test needs `cur realm`.
func TestCreatePollValidatesOptions(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	testing.SetRealm(testing.NewUserRealm(alice))

	id := CreatePoll(cross(cur), "best color?", "red, green , blue")
	if id != "poll #1 created with 3 options" {
		t.Fatalf("unexpected message: %q", id)
	}
	p := getPoll("1")
	if len(p.Options) != 3 || p.Options[0] != "red" || p.Options[2] != "blue" {
		t.Fatalf("options not parsed/trimmed correctly: %#v", p.Options)
	}

	if rec := revive(func() { CreatePoll(cross(cur), "one option?", "only-one") }); rec == nil {
		t.Fatal("expected panic for too few options")
	}
	if rec := revive(func() { CreatePoll(cross(cur), "  ", "a,b") }); rec == nil {
		t.Fatal("expected panic for empty question")
	}
}

func TestVoteQuadraticCostAndBudget(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	testing.SetRealm(testing.NewUserRealm(alice))
	CreatePoll(cross(cur), "pizza topping?", "pineapple,mushroom,pepperoni")

	// 1st vote costs 1, 2nd costs 3 more (4 total), 3rd costs 5 more (9 total).
	Vote(cross(cur), "1", 0, 1)
	vs := getOrCreateVoter("1", alice, 3)
	if vs.CreditsUsed != 1 {
		t.Fatalf("credits used = %d, want 1", vs.CreditsUsed)
	}
	Vote(cross(cur), "1", 0, 2)
	if vs.CreditsUsed != 9 || vs.Votes[0] != 3 {
		t.Fatalf("after buying to 3 votes: credits=%d votes=%d, want 9/3", vs.CreditsUsed, vs.Votes[0])
	}

	// Spending the rest of the 100-credit budget on another option should work
	// right up to the edge, then fail past it.
	Vote(cross(cur), "1", 1, 9) // 81 credits, total 90
	if vs.CreditsUsed != 90 {
		t.Fatalf("credits used = %d, want 90", vs.CreditsUsed)
	}
	if rec := revive(func() { Vote(cross(cur), "1", 2, 4) }); rec == nil { // would cost 16 more, total 106 > 100
		t.Fatal("expected panic for exceeding voice-credit budget")
	}

	p := getPoll("1")
	if p.Tally[0] != 3 || p.Tally[1] != 9 {
		t.Fatalf("unexpected tally: %#v", p.Tally)
	}
}

func TestVoteSellBackRefundsCredits(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	testing.SetRealm(testing.NewUserRealm(alice))
	CreatePoll(cross(cur), "best sea?", "north,baltic")

	Vote(cross(cur), "1", 0, 4) // 16 credits, 4 votes
	Vote(cross(cur), "1", 0, -1) // back to 3 votes: cost delta = 9-16 = -7

	vs := getOrCreateVoter("1", alice, 2)
	if vs.Votes[0] != 3 {
		t.Fatalf("votes = %d, want 3", vs.Votes[0])
	}
	if vs.CreditsUsed != 9 {
		t.Fatalf("credits used = %d, want 9", vs.CreditsUsed)
	}
	if getPoll("1").Tally[0] != 3 {
		t.Fatalf("tally = %d, want 3", getPoll("1").Tally[0])
	}

	if rec := revive(func() { Vote(cross(cur), "1", 0, -10) }); rec == nil {
		t.Fatal("expected panic for selling more votes than held")
	}
}

func TestClosePollOnlyCreator(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	bob := testutils.TestAddress("bob")

	testing.SetRealm(testing.NewUserRealm(alice))
	CreatePoll(cross(cur), "close me?", "yes,no")

	testing.SetRealm(testing.NewUserRealm(bob))
	if rec := revive(func() { ClosePoll(cross(cur), "1") }); rec == nil {
		t.Fatal("expected panic when a non-creator closes the poll")
	}

	testing.SetRealm(testing.NewUserRealm(alice))
	ClosePoll(cross(cur), "1")
	if !getPoll("1").Closed {
		t.Fatal("poll should be closed")
	}

	if rec := revive(func() { Vote(cross(cur), "1", 0, 1) }); rec == nil {
		t.Fatal("expected panic when voting on a closed poll")
	}
}

func TestRenderNoPolls(t *testing.T) {
	resetState()
	out := Render("")
	if !strings.Contains(out, "no polls yet") {
		t.Fatalf("expected empty-state message, got: %s", out)
	}
}

func TestRenderPollNotFound(t *testing.T) {
	resetState()
	out := Render("42")
	if !strings.Contains(out, "No such poll") {
		t.Fatalf("expected not-found message, got: %s", out)
	}
}

