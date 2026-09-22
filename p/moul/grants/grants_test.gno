package grants

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

var (
	alice   = testutils.TestAddress("alice")   // member
	bob     = testutils.TestAddress("bob")     // member
	carol   = testutils.TestAddress("carol")   // member
	dave    = testutils.TestAddress("dave")    // applicant, not a member
	mallory = testutils.TestAddress("mallory") // nobody
)

// board3 is the fixture most tests want: three members, so a majority of the
// eligible set is two whenever the applicant is an outsider.
func board3() *Board { return New(alice, bob, carol) }

// submitOne files a two-milestone grant from dave, the outsider applicant.
func submitOne(t *testing.T, b *Board) *Request {
	t.Helper()
	r, err := b.Submit(dave, "Port the thing", "with tests",
		[]*Milestone{NewMilestone("design", 100), NewMilestone("ship", 400)}, 10)
	urequire.NoError(t, err)
	return r
}

func TestNewSeedsFoundersAtHeightZero(t *testing.T) {
	b := board3()
	uassert.Equal(t, 3, b.MemberCount())
	for _, m := range []address{alice, bob, carol} {
		uassert.True(t, b.IsMember(m), m.String()+" should be a founder")
		uassert.Equal(t, int64(0), b.JoinedAt(m))
	}
	uassert.False(t, b.IsMember(dave))
	uassert.Equal(t, int64(-1), b.JoinedAt(dave))

	// Members is address-ordered, and the order is what avl gives, not
	// insertion order. Only the stability matters, so compare two calls.
	first, second := b.Members(), b.Members()
	urequire.Equal(t, 3, len(first))
	for i := range first {
		uassert.Equal(t, first[i].String(), second[i].String())
	}
}

func TestNewSkipsInvalidFounders(t *testing.T) {
	b := New(alice, address(""), alice)
	uassert.Equal(t, 1, b.MemberCount(), "empty address dropped, duplicate collapsed")
}

func TestSubmitValidation(t *testing.T) {
	long := ""
	for i := 0; i < MaxTitle+1; i++ {
		long += "x"
	}
	body := ""
	for i := 0; i < MaxBody+1; i++ {
		body += "y"
	}
	many := make([]*Milestone, MaxMilestones+1)
	for i := range many {
		many[i] = NewMilestone("m", 1)
	}

	cases := []struct {
		name  string
		title string
		body  string
		ms    []*Milestone
		want  error
	}{
		{"ok", "t", "b", []*Milestone{NewMilestone("m", 1)}, nil},
		{"empty title", "", "b", []*Milestone{NewMilestone("m", 1)}, ErrBadTitle},
		{"long title", long, "b", []*Milestone{NewMilestone("m", 1)}, ErrBadTitle},
		{"long body", "t", body, []*Milestone{NewMilestone("m", 1)}, ErrBadBody},
		{"no milestone", "t", "b", nil, ErrBadMilestones},
		{"too many milestones", "t", "b", many, ErrBadMilestones},
		{"zero amount", "t", "b", []*Milestone{NewMilestone("m", 0)}, ErrBadAmount},
		{"negative amount", "t", "b", []*Milestone{NewMilestone("m", -1)}, ErrBadAmount},
		{"untitled milestone", "t", "b", []*Milestone{NewMilestone("", 1)}, ErrBadTitle},
	}
	for _, tc := range cases {
		_, err := board3().Submit(dave, tc.title, tc.body, tc.ms, 1)
		if tc.want == nil {
			uassert.NoError(t, err, tc.name)
			continue
		}
		uassert.ErrorIs(t, err, tc.want, tc.name)
	}

	_, err := board3().Submit(address(""), "t", "b", []*Milestone{NewMilestone("m", 1)}, 1)
	uassert.ErrorIs(t, err, ErrBadAddress, "invalid applicant")
}

func TestRequestArithmetic(t *testing.T) {
	b := board3()
	r := submitOne(t, b)
	uassert.Equal(t, int64(500), r.Total())
	uassert.Equal(t, int64(0), r.Paid())
	uassert.Equal(t, int64(0), r.Outstanding(), "a pending grant commits nothing")
	uassert.Equal(t, 0, r.Next())
	uassert.Equal(t, "pending", r.Status.String())
	uassert.Equal(t, "grant", r.Kind.String())
	uassert.True(t, r.Excludes(dave), "the applicant never votes on their own grant")
	uassert.False(t, r.Excludes(alice))
	uassert.Equal(t, dave.String(), r.Payee().String(), "a self request pays its applicant")
	uassert.False(t, r.OnBehalf())
	uassert.Equal(t, 1, r.ID)
	uassert.Equal(t, r.ID, b.Get(1).ID)
	uassert.True(t, b.Get(42) == nil, "unknown id")
}

func TestMajorityCountsOnlyEligibleMembers(t *testing.T) {
	b := board3()

	outsider := submitOne(t, b)
	uassert.Equal(t, 3, b.Eligible(outsider))
	uassert.Equal(t, 2, b.Majority(outsider))

	// A member applying for their own grant shrinks the eligible set, and
	// with it the bar: two of the remaining two must agree.
	insider, err := b.Submit(alice, "self", "", []*Milestone{NewMilestone("m", 1)}, 1)
	urequire.NoError(t, err)
	uassert.Equal(t, 2, b.Eligible(insider))
	uassert.Equal(t, 2, b.Majority(insider))
}

func TestApprovalNeedsAMajority(t *testing.T) {
	b := board3()
	r := submitOne(t, b)

	st, err := b.Vote(alice, r.ID, true, "good", 11)
	urequire.NoError(t, err)
	uassert.Equal(t, "pending", st.String(), "one of three is not a majority")

	st, err = b.Vote(bob, r.ID, true, "agreed", 12)
	urequire.NoError(t, err)
	uassert.Equal(t, "approved", st.String())
	uassert.Equal(t, int64(12), r.DecidedAt)
	uassert.Equal(t, int64(500), r.Outstanding(), "approval commits the full ask")
	uassert.Equal(t, int64(500), b.Committed())

	yes, no := r.Tally()
	uassert.Equal(t, 2, yes)
	uassert.Equal(t, 0, no)
	uassert.Equal(t, "good", r.BallotOf(alice).Reason)
	uassert.True(t, r.BallotOf(carol) == nil, "carol never voted")
}

func TestRejectionNeedsAMajorityToo(t *testing.T) {
	b := board3()
	r := submitOne(t, b)
	urequire.NoError(t, errOf(b.Vote(alice, r.ID, false, "out of scope", 11)))
	st, err := b.Vote(bob, r.ID, false, "same", 12)
	urequire.NoError(t, err)
	uassert.Equal(t, "rejected", st.String())
	uassert.Equal(t, int64(0), b.Committed(), "a rejected grant commits nothing")
}

func TestVoteRefusals(t *testing.T) {
	b := board3()
	r := submitOne(t, b)
	self, err := b.Submit(alice, "self", "", []*Milestone{NewMilestone("m", 1)}, 1)
	urequire.NoError(t, err)

	_, err = b.Vote(alice, 999, true, "", 1)
	uassert.ErrorIs(t, err, ErrNoRequest)

	_, err = b.Vote(mallory, r.ID, true, "", 1)
	uassert.ErrorIs(t, err, ErrNotMember)

	_, err = b.Vote(alice, self.ID, true, "vote for myself", 1)
	uassert.ErrorIs(t, err, ErrConflict)

	long := ""
	for i := 0; i < MaxReason+1; i++ {
		long += "z"
	}
	_, err = b.Vote(alice, r.ID, true, long, 1)
	uassert.ErrorIs(t, err, ErrBadReason)

	urequire.NoError(t, errOf(b.Vote(alice, r.ID, true, "yes", 1)))
	_, err = b.Vote(alice, r.ID, false, "changed my mind", 2)
	uassert.ErrorIs(t, err, ErrAlreadyVoted, "a ballot is permanent")

	urequire.NoError(t, errOf(b.Vote(bob, r.ID, true, "yes", 3)))
	_, err = b.Vote(carol, r.ID, true, "too late", 4)
	uassert.ErrorIs(t, err, ErrNotPending, "decided requests take no more ballots")
}

func TestDecidesPreviewsWithoutCasting(t *testing.T) {
	b := board3()
	r := submitOne(t, b)

	settles, to := b.Decides(r.ID, alice, true)
	uassert.False(t, settles, "the first of three does not settle it")
	uassert.Equal(t, 0, len(r.Votes), "previewing casts nothing")

	urequire.NoError(t, errOf(b.Vote(alice, r.ID, true, "", 11)))
	settles, to = b.Decides(r.ID, bob, true)
	uassert.True(t, settles)
	uassert.Equal(t, "approved", to.String())

	settles, _ = b.Decides(r.ID, bob, false)
	uassert.False(t, settles, "a no here only makes it one-all")

	settles, _ = b.Decides(r.ID, mallory, true)
	uassert.False(t, settles, "a non-member decides nothing")
	settles, _ = b.Decides(r.ID, alice, true)
	uassert.False(t, settles, "a member who already voted decides nothing")
	settles, _ = b.Decides(999, bob, true)
	uassert.False(t, settles, "an unknown request decides nothing")
}

func TestWithdraw(t *testing.T) {
	b := board3()
	r := submitOne(t, b)

	uassert.ErrorIs(t, b.Withdraw(mallory, r.ID, 5), ErrNotApplicant)
	uassert.ErrorIs(t, b.Withdraw(dave, 999, 5), ErrNoRequest)
	urequire.NoError(t, b.Withdraw(dave, r.ID, 5))
	uassert.Equal(t, "withdrawn", r.Status.String())
	uassert.ErrorIs(t, b.Withdraw(dave, r.ID, 6), ErrNotPending)
}

func TestProofRefusals(t *testing.T) {
	b := board3()
	r := submitOne(t, b)
	good := Proof{Kind: "url", Ref: "https://example.com/pr/1", Height: 20}

	uassert.ErrorIs(t, b.SubmitProof(dave, r.ID, 0, good), ErrNotApproved, "not approved yet")

	urequire.NoError(t, errOf(b.Vote(alice, r.ID, true, "", 11)))
	urequire.NoError(t, errOf(b.Vote(bob, r.ID, true, "", 12)))

	uassert.ErrorIs(t, b.SubmitProof(mallory, r.ID, 0, good), ErrNotApplicant)
	uassert.ErrorIs(t, b.SubmitProof(dave, r.ID, 7, good), ErrNoMilestone)
	uassert.ErrorIs(t, b.SubmitProof(dave, r.ID, 1, good), ErrOutOfOrder, "milestone 1 before 0")

	bad := []Proof{
		{Kind: "screenshot", Ref: "x"},
		{Kind: "url", Ref: ""},
		{Kind: "text", Ref: "ok", Note: longString(MaxNote + 1)},
		{Kind: "url", Ref: longString(MaxRef + 1)},
	}
	for _, p := range bad {
		uassert.ErrorIs(t, b.SubmitProof(dave, r.ID, 0, p), ErrBadProof, p.Kind)
	}

	urequire.NoError(t, b.SubmitProof(dave, r.ID, 0, good))
	uassert.ErrorIs(t, b.SubmitProof(dave, r.ID, 0, good), ErrProofPending, "one at a time")
}

func TestReleaseRunsThroughToCompletion(t *testing.T) {
	b := board3()
	r := submitOne(t, b)
	urequire.NoError(t, errOf(b.Vote(alice, r.ID, true, "", 11)))
	urequire.NoError(t, errOf(b.Vote(bob, r.ID, true, "", 12)))

	// Milestone 0.
	urequire.NoError(t, b.SubmitProof(dave, r.ID, 0, Proof{Kind: "url", Ref: "https://x/1", Height: 20}))
	out, err := b.Review(alice, r.ID, 0, true, "looks done", 21)
	urequire.NoError(t, err)
	uassert.Equal(t, "under review", out.String(), "one reviewer is not a majority")
	uassert.False(t, r.Milestones[0].Released)

	out, err = b.Review(carol, r.ID, 0, true, "confirmed", 22)
	urequire.NoError(t, err)
	uassert.Equal(t, "accepted", out.String())
	uassert.True(t, r.Milestones[0].Released)
	uassert.Equal(t, int64(22), r.Milestones[0].ReleasedAt)
	uassert.Equal(t, int64(100), r.Paid())
	uassert.Equal(t, int64(400), r.Outstanding())
	uassert.Equal(t, "approved", r.Status.String(), "one tranche left")
	uassert.Equal(t, 1, r.Next())

	// Milestone 1 completes the grant.
	urequire.NoError(t, b.SubmitProof(dave, r.ID, 1, Proof{Kind: "hash", Ref: "deadbeef", Height: 30}))
	urequire.NoError(t, errOf2(b.Review(alice, r.ID, 1, true, "", 31)))
	out, err = b.Review(bob, r.ID, 1, true, "", 32)
	urequire.NoError(t, err)
	uassert.Equal(t, "accepted", out.String())
	uassert.Equal(t, "completed", r.Status.String())
	uassert.Equal(t, -1, r.Next())
	uassert.Equal(t, int64(500), r.Paid())
	uassert.Equal(t, int64(0), r.Outstanding(), "a completed grant commits nothing")
	uassert.Equal(t, int64(500), b.Disbursed())
	uassert.Equal(t, int64(0), b.Committed())
}

func TestRefusedProofKeepsTheGrantAliveAndOnTheRecord(t *testing.T) {
	b := board3()
	r := submitOne(t, b)
	urequire.NoError(t, errOf(b.Vote(alice, r.ID, true, "", 11)))
	urequire.NoError(t, errOf(b.Vote(bob, r.ID, true, "", 12)))

	urequire.NoError(t, b.SubmitProof(dave, r.ID, 0, Proof{Kind: "url", Ref: "https://x/draft", Height: 20}))
	urequire.NoError(t, errOf2(b.Review(alice, r.ID, 0, false, "this is a stub", 21)))
	out, err := b.Review(bob, r.ID, 0, false, "agreed, no tests", 22)
	urequire.NoError(t, err)
	uassert.Equal(t, "refused", out.String())
	uassert.False(t, r.Milestones[0].Released)
	uassert.Equal(t, "approved", r.Status.String(), "a refused proof does not kill the grant")

	// The refused attempt stays readable, reasons and all.
	m := r.Milestones[0]
	urequire.Equal(t, 1, len(m.Attempts))
	uassert.Equal(t, "this is a stub", m.Attempts[0].Reviews[0].Reason)
	uassert.True(t, m.Current() == nil, "the attempt is closed")

	// And a second attempt can carry.
	urequire.NoError(t, b.SubmitProof(dave, r.ID, 0, Proof{Kind: "url", Ref: "https://x/final", Height: 30}))
	urequire.NoError(t, errOf2(b.Review(alice, r.ID, 0, true, "now it is done", 31)))
	urequire.NoError(t, errOf2(b.Review(bob, r.ID, 0, true, "", 32)))
	uassert.True(t, r.Milestones[0].Released)
	uassert.Equal(t, 2, len(m.Attempts), "both attempts are kept")
}

func TestReviewRefusals(t *testing.T) {
	b := board3()
	r := submitOne(t, b)
	urequire.NoError(t, errOf(b.Vote(alice, r.ID, true, "", 11)))
	urequire.NoError(t, errOf(b.Vote(bob, r.ID, true, "", 12)))

	uassert.ErrorIs(t, errOf2(b.Review(alice, r.ID, 0, true, "", 20)), ErrNoProof)
	urequire.NoError(t, b.SubmitProof(dave, r.ID, 0, Proof{Kind: "text", Ref: "done", Height: 20}))

	uassert.ErrorIs(t, errOf2(b.Review(mallory, r.ID, 0, true, "", 21)), ErrNotMember)
	uassert.ErrorIs(t, errOf2(b.Review(alice, 999, 0, true, "", 21)), ErrNoRequest)
	uassert.ErrorIs(t, errOf2(b.Review(alice, r.ID, 9, true, "", 21)), ErrNoMilestone)
	urequire.NoError(t, errOf2(b.Review(alice, r.ID, 0, true, "", 21)))
	uassert.ErrorIs(t, errOf2(b.Review(alice, r.ID, 0, false, "", 22)), ErrAlreadyVoted)
}

func TestApplicantMayNotReviewTheirOwnProof(t *testing.T) {
	b := New(alice, bob, dave) // dave is a member AND the applicant here
	r, err := b.Submit(dave, "self funded", "", []*Milestone{NewMilestone("m", 10)}, 1)
	urequire.NoError(t, err)
	urequire.NoError(t, errOf(b.Vote(alice, r.ID, true, "", 2)))
	urequire.NoError(t, errOf(b.Vote(bob, r.ID, true, "", 3)))
	urequire.NoError(t, b.SubmitProof(dave, r.ID, 0, Proof{Kind: "text", Ref: "done", Height: 4}))
	uassert.ErrorIs(t, errOf2(b.Review(dave, r.ID, 0, true, "ship it", 5)), ErrConflict)
}

func TestMembershipRequestAddsAndRemoves(t *testing.T) {
	b := board3()

	add, err := b.SubmitMemberChange(alice, dave, true, "he reviews everything anyway", 5)
	urequire.NoError(t, err)
	uassert.Equal(t, "membership", add.Kind.String())
	uassert.Equal(t, "Add "+dave.String(), add.Title)
	uassert.Equal(t, int64(0), add.Total(), "a membership request asks for no money")

	urequire.NoError(t, errOf(b.Vote(alice, add.ID, true, "", 6)))
	st, err := b.Vote(bob, add.ID, true, "", 7)
	urequire.NoError(t, err)
	uassert.Equal(t, "completed", st.String(), "membership executes on approval")
	uassert.True(t, b.IsMember(dave))
	uassert.Equal(t, int64(7), b.JoinedAt(dave), "joined at the deciding height")

	// Now four members: a majority excluding the subject is still two.
	rm, err := b.SubmitMemberChange(alice, carol, false, "inactive", 8)
	urequire.NoError(t, err)
	uassert.Equal(t, 3, b.Eligible(rm))
	uassert.ErrorIs(t, errOf(b.Vote(carol, rm.ID, false, "no", 9)), ErrConflict, "the subject may not vote")
	urequire.NoError(t, errOf(b.Vote(alice, rm.ID, true, "", 10)))
	urequire.NoError(t, errOf(b.Vote(bob, rm.ID, true, "", 11)))
	uassert.False(t, b.IsMember(carol))
	uassert.Equal(t, 3, b.MemberCount())
}

func TestMemberChangeRefusals(t *testing.T) {
	b := board3()

	_, err := b.SubmitMemberChange(mallory, dave, true, "", 1)
	uassert.ErrorIs(t, err, ErrNotMember, "only members touch the board's composition")
	_, err = b.SubmitMemberChange(alice, alice, true, "", 1)
	uassert.ErrorIs(t, err, ErrIsMember)
	_, err = b.SubmitMemberChange(alice, dave, false, "", 1)
	uassert.ErrorIs(t, err, ErrNotMember, "cannot remove a non-member")
	_, err = b.SubmitMemberChange(alice, address(""), true, "", 1)
	uassert.ErrorIs(t, err, ErrBadAddress)

	solo := New(alice)
	_, err = solo.SubmitMemberChange(alice, alice, false, "", 1)
	uassert.ErrorIs(t, err, ErrLastMember, "the board cannot empty itself")
}

// Standing is the whole reason a removed member's yes does not keep carrying
// decisions they are no longer part of.
func TestStandingDropsBallotsFromFormerMembers(t *testing.T) {
	b := board3()
	r := submitOne(t, b)
	urequire.NoError(t, errOf(b.Vote(carol, r.ID, true, "I like it", 11)))

	rm, err := b.SubmitMemberChange(alice, carol, false, "left the project", 12)
	urequire.NoError(t, err)
	urequire.NoError(t, errOf(b.Vote(alice, rm.ID, true, "", 13)))
	urequire.NoError(t, errOf(b.Vote(bob, rm.ID, true, "", 14)))
	urequire.Equal(t, 2, b.MemberCount())

	yes, _ := r.Tally()
	uassert.Equal(t, 1, yes, "the ballot stays on the record")
	yes, _ = b.Standing(r)
	uassert.Equal(t, 0, yes, "but it no longer counts")

	// With two members and an outsider applicant the bar is two, so alice
	// alone still cannot carry it.
	uassert.Equal(t, 2, b.Majority(r))
	st, err := b.Vote(alice, r.ID, true, "", 15)
	urequire.NoError(t, err)
	uassert.Equal(t, "pending", st.String())
}

func TestListAndSizeStayInIDOrder(t *testing.T) {
	b := board3()
	for i := 0; i < 12; i++ {
		_, err := b.Submit(dave, "r", "", []*Milestone{NewMilestone("m", 1)}, int64(i))
		urequire.NoError(t, err)
	}
	all := b.List()
	urequire.Equal(t, 12, len(all))
	uassert.Equal(t, 12, b.Size())
	for i, r := range all {
		uassert.Equal(t, i+1, r.ID, "ids come back in numeric order past nine")
	}
}

func longString(n int) string {
	s := ""
	for i := 0; i < n; i++ {
		s += "x"
	}
	return s
}

// errOf and errOf2 drop the leading return value of Vote and Review so a call
// reads as a single assertion.
func errOf(_ Status, err error) error   { return err }
func errOf2(_ Outcome, err error) error { return err }

func TestFilingForSomeoneElseNeedsAReason(t *testing.T) {
	b := board3()
	ms := func() []*Milestone { return []*Milestone{NewMilestone("m", 100)} }

	_, err := b.SubmitFor(dave, mallory, "", "t", "", ms(), 10)
	uassert.ErrorIs(t, err, ErrNeedReason, "a request for someone else has to say why")

	// The same address is just a self request, and needs nothing extra.
	self, err := b.SubmitFor(dave, dave, "", "t", "", ms(), 10)
	urequire.NoError(t, err)
	uassert.False(t, self.OnBehalf())

	_, err = b.SubmitFor(dave, address("not-an-address"), "because", "t", "", ms(), 10)
	uassert.ErrorIs(t, err, ErrBadAddress)

	long := ""
	for i := 0; i <= MaxReason; i++ {
		long += "x"
	}
	_, err = b.SubmitFor(dave, mallory, long, "t", "", ms(), 10)
	uassert.ErrorIs(t, err, ErrBadReason)

	r, err := b.SubmitFor(dave, mallory, "their account is empty", "t", "", ms(), 10)
	urequire.NoError(t, err)
	uassert.True(t, r.OnBehalf())
	uassert.Equal(t, mallory.String(), r.Payee().String())
	uassert.Equal(t, dave.String(), r.Applicant.String())
}

// A member who is paid by a request someone else filed is the same conflict of
// interest as a member who filed it, with one address in between.
func TestBothPartiesAreBarredFromVotingOnAGrant(t *testing.T) {
	b := board3()
	r, err := b.SubmitFor(alice, bob, "bob asked me to file it", "t", "",
		[]*Milestone{NewMilestone("m", 100)}, 10)
	urequire.NoError(t, err)

	uassert.True(t, r.Excludes(alice), "the applicant")
	uassert.True(t, r.Excludes(bob), "the beneficiary")
	uassert.False(t, r.Excludes(carol))
	uassert.Equal(t, 1, b.Eligible(r), "three members, two of them party to it")
	uassert.Equal(t, 1, b.Majority(r))

	_, err = b.Vote(alice, r.ID, true, "", 11)
	uassert.ErrorIs(t, err, ErrConflict, "the applicant may not vote")
	_, err = b.Vote(bob, r.ID, true, "", 11)
	uassert.ErrorIs(t, err, ErrConflict, "the payee may not vote")

	st, err := b.Vote(carol, r.ID, true, "fine", 12)
	urequire.NoError(t, err)
	uassert.Equal(t, "approved", st.String(), "the one eligible member carries it")

	// And the same exclusion holds on the proof review, which is where the
	// money actually moves.
	urequire.NoError(t, b.SubmitProof(alice, r.ID, 0, Proof{Kind: "text", Ref: "done", Height: 13}))
	_, err = b.Review(bob, r.ID, 0, true, "", 14)
	uassert.ErrorIs(t, err, ErrConflict, "the payee may not review their own proof")
}

// The payee of a request filed for an empty account cannot transact until the
// first tranche lands, so the filer has to be able to prove the work; once the
// payee can transact, they have to be able to prove their own.
func TestEitherPartyMaySubmitAProof(t *testing.T) {
	b := board3()
	r, err := b.SubmitFor(dave, mallory, "empty account", "t", "",
		[]*Milestone{NewMilestone("one", 100), NewMilestone("two", 100)}, 10)
	urequire.NoError(t, err)
	b.Vote(alice, r.ID, true, "", 11)
	b.Vote(bob, r.ID, true, "", 12)
	urequire.Equal(t, "approved", r.Status.String())

	uassert.ErrorIs(t, b.SubmitProof(carol, r.ID, 0, Proof{Kind: "text", Ref: "x", Height: 13}),
		ErrNotApplicant, "a third party may not")

	urequire.NoError(t, b.SubmitProof(dave, r.ID, 0, Proof{Kind: "text", Ref: "filer", Height: 13}))
	b.Review(alice, r.ID, 0, true, "", 14)
	b.Review(bob, r.ID, 0, true, "", 15)
	urequire.True(t, r.Milestones[0].Released)

	urequire.NoError(t, b.SubmitProof(mallory, r.ID, 1, Proof{Kind: "text", Ref: "payee", Height: 16}))
}
