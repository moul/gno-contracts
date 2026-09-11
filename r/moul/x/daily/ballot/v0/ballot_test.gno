package ballot

import (
	"strings"
	"testing"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/testutils/v0"
)

func resetState() {
	var zero address
	chairperson = zero
	initialized = false
	proposals = nil
	voters = avl.NewTree()
}

// Crossing: Init/Vote/Delegate/GiveRightToVote mutate realm state, so tests
// that call them need `cur realm`.
func TestInitSetsChairpersonAndProposals(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")

	testing.SetRealm(testing.NewUserRealm(alice))
	Init(cross(cur), "Alice, Bob , Carol")

	if chairperson != alice {
		t.Fatal("chairperson should be the Init caller")
	}
	if len(proposals) != 3 {
		t.Fatalf("len(proposals) = %d, want 3", len(proposals))
	}
	if proposals[0].name != "Alice" || proposals[1].name != "Bob" || proposals[2].name != "Carol" {
		t.Fatal("proposal names should be trimmed and in order")
	}

	rec := revive(func() { Init(cross(cur), "X") })
	if rec == nil {
		t.Fatal("expected panic on double Init")
	}
}

func TestGiveRightToVoteOnlyChairperson(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	bob := testutils.TestAddress("bob")
	mallory := testutils.TestAddress("mallory")

	testing.SetRealm(testing.NewUserRealm(alice))
	Init(cross(cur), "A,B")

	testing.SetRealm(testing.NewUserRealm(mallory))
	rec := revive(func() { GiveRightToVote(cross(cur), bob.String()) })
	if rec == nil {
		t.Fatal("expected panic when a non-chairperson grants voting rights")
	}

	testing.SetRealm(testing.NewUserRealm(alice))
	GiveRightToVote(cross(cur), bob.String())

	v := voters.Get(bob.String())
	if v == nil || v.(*voterInfo).weight != 1 {
		t.Fatal("bob should now have voting weight 1")
	}
}

func TestVoteDirectly(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")

	testing.SetRealm(testing.NewUserRealm(alice))
	Init(cross(cur), "A,B")
	Vote(cross(cur), 1)

	if proposals[1].votes != 1 {
		t.Fatalf("proposals[1].votes = %d, want 1", proposals[1].votes)
	}
	if WinnerName() != "B" {
		t.Fatalf("WinnerName() = %q, want B", WinnerName())
	}

	rec := revive(func() { Vote(cross(cur), 0) })
	if rec == nil {
		t.Fatal("expected panic on double vote")
	}
}

func TestDelegateToUnvotedAccumulatesWeight(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	bob := testutils.TestAddress("bob")

	testing.SetRealm(testing.NewUserRealm(alice))
	Init(cross(cur), "A,B")
	GiveRightToVote(cross(cur), bob.String())

	testing.SetRealm(testing.NewUserRealm(bob))
	Delegate(cross(cur), alice.String())

	aliceVoter := voters.Get(alice.String())
	if aliceVoter.(*voterInfo).weight != 2 {
		t.Fatalf("alice.weight = %d, want 2", aliceVoter.(*voterInfo).weight)
	}

	testing.SetRealm(testing.NewUserRealm(alice))
	Vote(cross(cur), 0)

	if proposals[0].votes != 2 {
		t.Fatalf("proposals[0].votes = %d, want 2 (alice's own weight + bob's delegation)", proposals[0].votes)
	}
}

func TestDelegateToAlreadyVotedAddsDirectly(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	bob := testutils.TestAddress("bob")

	testing.SetRealm(testing.NewUserRealm(alice))
	Init(cross(cur), "A,B")
	GiveRightToVote(cross(cur), bob.String())
	Vote(cross(cur), 1)

	testing.SetRealm(testing.NewUserRealm(bob))
	Delegate(cross(cur), alice.String())

	if proposals[1].votes != 2 {
		t.Fatalf("proposals[1].votes = %d, want 2 (alice's vote + bob's delegated weight)", proposals[1].votes)
	}
}

func TestSelfDelegatePanics(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")

	testing.SetRealm(testing.NewUserRealm(alice))
	Init(cross(cur), "A,B")

	rec := revive(func() { Delegate(cross(cur), alice.String()) })
	if rec == nil {
		t.Fatal("expected panic on self-delegation")
	}
}

func TestDelegateLoopPanics(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	bob := testutils.TestAddress("bob")
	carol := testutils.TestAddress("carol")

	testing.SetRealm(testing.NewUserRealm(alice))
	Init(cross(cur), "A,B")
	GiveRightToVote(cross(cur), bob.String())
	GiveRightToVote(cross(cur), carol.String())

	// alice -> bob
	testing.SetRealm(testing.NewUserRealm(alice))
	Delegate(cross(cur), bob.String())

	// carol -> alice would close the loop carol -> alice -> bob if bob then
	// delegated back to carol; instead exercise the direct A -> B -> A cycle:
	testing.SetRealm(testing.NewUserRealm(carol))
	rec := revive(func() {
		// bob has no delegate yet (he's an accumulation point), so seed a
		// cycle by having carol delegate to bob, then bob delegate to carol.
		Delegate(cross(cur), bob.String())
	})
	if rec != nil {
		t.Fatal("carol -> bob should succeed (bob hasn't voted or delegated)")
	}

	testing.SetRealm(testing.NewUserRealm(bob))
	rec = revive(func() { Delegate(cross(cur), carol.String()) })
	if rec == nil {
		t.Fatal("expected panic when closing a delegation loop (bob -> carol -> bob)")
	}
}

func TestWinningProposalTieBreaksLowestIndex(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")
	bob := testutils.TestAddress("bob")

	testing.SetRealm(testing.NewUserRealm(alice))
	Init(cross(cur), "A,B,C")
	GiveRightToVote(cross(cur), bob.String())
	Vote(cross(cur), 1)

	testing.SetRealm(testing.NewUserRealm(bob))
	Vote(cross(cur), 0)

	if WinningProposal() != 0 {
		t.Fatalf("WinningProposal() = %d, want 0 (tie broken toward lowest index)", WinningProposal())
	}
}

// Non-crossing: Render is a plain read.
func TestRenderBeforeInit(t *testing.T) {
	resetState()
	if out := Render(""); out == "" {
		t.Fatal(`Render("") should not be empty before Init`)
	}
}

func TestRenderAfterInit(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")

	testing.SetRealm(testing.NewUserRealm(alice))
	Init(cross(cur), "A,B")
	Vote(cross(cur), 0)

	out := Render("")
	if !strings.Contains(out, "A") || !strings.Contains(out, alice.String()) {
		t.Fatal("Render should include the proposal names and the chairperson address")
	}
}
