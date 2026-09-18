package grantsdao

import (
	"chain"
	"chain/banker"
	"testing"

	"gno.land/p/moul/x/grants/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

// The seeded cast, plus one outsider the seed never mentions.
const (
	alice = address("g1manfred47kzduec920z88wfr64ylksmdcedlf5") // founder
	bob   = address("g1us8428u2a5satrlxzagqqa5m6vmuze025anjlj") // founder
	carol = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5") // founder
	dan   = seedMember                                          // co-opted by the seed
	eve   = seedApplicant                                       // the seeded applicant
	zoe   = address("g12cs4cehujpffpjpywmkqj43m6u5ya53nj69sjz") // nobody
)

func balanceOf(a address) int64 {
	return banker.NewReadonlyBanker().GetCoins(a).AmountOf(Denom)
}

func fund(n int64) { testing.IssueCoins(Address(), chain.NewCoins(chain.NewCoin(Denom, n))) }

func TestFoundersAreRealAddresses(t *testing.T) {
	for _, f := range Founders {
		uassert.True(t, f.IsValid(), f.String())
	}
	for _, a := range []address{dan, eve, zoe, seedMember, seedApplicant, seedRejected} {
		uassert.True(t, a.IsValid(), a.String())
	}
	uassert.True(t, Address().IsValid(), "the treasury address")
}

func TestSeedLeavesTheBoardMidFlight(t *testing.T) {
	seed()

	uassert.Equal(t, 4, board.MemberCount(), "three founders plus the co-opted seat")
	uassert.True(t, board.IsMember(dan), "the membership request executed")
	uassert.Equal(t, int64(102), board.JoinedAt(dan))
	uassert.Equal(t, 3, board.Size())

	uassert.Equal(t, "completed", board.Get(1).Status.String(), "membership change")
	uassert.Equal(t, "approved", board.Get(2).Status.String(), "the grant in flight")
	uassert.Equal(t, "rejected", board.Get(3).Status.String(), "the one turned down")

	g := board.Get(2)
	uassert.Equal(t, int64(2000), g.Total())
	uassert.Equal(t, int64(0), g.Paid(), "a seed cannot mint a treasury, so nothing was paid")
	uassert.Equal(t, int64(2000), g.Outstanding())
	uassert.Equal(t, 4, len(g.Votes), "three for, one against, all with reasons")
	urequire.NotEqual(t, nil, g.Milestones[0].Current())
	uassert.Equal(t, 1, len(g.Milestones[0].Current().Reviews), "one accept, two short of a majority")

	uassert.Equal(t, int64(2000), Committed())
	uassert.Equal(t, int64(0), Disbursed())
	uassert.Equal(t, int64(0), Raised())
	uassert.Equal(t, 0, len(payments))
}

func TestParseMilestones(t *testing.T) {
	cases := []struct {
		name    string
		spec    string
		titles  []string
		amounts []int64
	}{
		{"one", "ship:400", []string{"ship"}, []int64{400}},
		{"two", "design:100,ship:400", []string{"design", "ship"}, []int64{100, 400}},
		{"spaces", " design : 100 , ship : 400 ", []string{"design", "ship"}, []int64{100, 400}},
		{"trailing comma", "ship:400,", []string{"ship"}, []int64{400}},
		{"colon in the title", "port gno:land tooling:250", []string{"port gno:land tooling"}, []int64{250}},
	}
	for _, tc := range cases {
		ms, err := parseMilestones(tc.spec)
		if !uassert.NoError(t, err, tc.name) {
			continue
		}
		urequire.Equal(t, len(tc.titles), len(ms), tc.name)
		for i := range ms {
			uassert.Equal(t, tc.titles[i], ms[i].Title, tc.name)
			uassert.Equal(t, tc.amounts[i], ms[i].Amount, tc.name)
		}
	}

	for _, bad := range []string{"", "  ", ",,", "ship", "ship:", "ship:many", "ship:1:2:x"} {
		_, err := parseMilestones(bad)
		uassert.ErrorIs(t, err, ErrBadSpec, "should be rejected: "+bad)
	}
}

func TestApplyIsOpenToAnyoneAndVotingIsNot(cur realm, t *testing.T) {
	seed()

	testing.SetRealm(testing.NewUserRealm(zoe))
	id := Apply(cross(cur), "Write the docs", "for the thing", "outline:10,draft:20,final:30")
	uassert.Equal(t, 4, id)

	r := board.Get(id)
	urequire.NotEqual(t, nil, r)
	uassert.Equal(t, zoe.String(), r.Applicant.String())
	uassert.Equal(t, int64(60), r.Total())
	uassert.Equal(t, 3, len(r.Milestones))
	uassert.Equal(t, "pending", r.Status.String())

	// A non-member cannot vote.
	testing.SetRealm(testing.NewUserRealm(zoe))
	uassert.AbortsContains(t, cur, grants.ErrNotMember.Error(), func() {
		Vote(cross(cur), id, true, "me again")
	})

	// Four members, an outsider applicant: three have to agree.
	testing.SetRealm(testing.NewUserRealm(alice))
	Vote(cross(cur), id, true, "cheap")
	testing.SetRealm(testing.NewUserRealm(bob))
	Vote(cross(cur), id, true, "fine")
	uassert.Equal(t, "pending", board.Get(id).Status.String(), "two of four is not a majority")
	testing.SetRealm(testing.NewUserRealm(carol))
	Vote(cross(cur), id, true, "yes")
	uassert.Equal(t, "approved", board.Get(id).Status.String())

	// And the ballots are all on the record, with their reasons.
	urequire.Equal(t, 3, len(r.Votes))
	uassert.Equal(t, "cheap", r.Votes[0].Reason)
	uassert.Equal(t, alice.String(), r.Votes[0].Voter.String())
}

func TestRetractIsTheApplicantsOwn(cur realm, t *testing.T) {
	seed()
	testing.SetRealm(testing.NewUserRealm(zoe))
	id := Apply(cross(cur), "Never mind", "", "thing:1")

	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, grants.ErrNotApplicant.Error(), func() {
		Retract(cross(cur), id)
	})
	testing.SetRealm(testing.NewUserRealm(zoe))
	Retract(cross(cur), id)
	uassert.Equal(t, "withdrawn", board.Get(id).Status.String())
}

func TestProposeMemberIsMembersOnly(cur realm, t *testing.T) {
	seed()
	testing.SetRealm(testing.NewUserRealm(zoe))
	uassert.AbortsContains(t, cur, grants.ErrNotMember.Error(), func() {
		ProposeMember(cross(cur), zoe.String(), true, "let me in")
	})

	testing.SetRealm(testing.NewUserRealm(alice))
	id := ProposeMember(cross(cur), zoe.String(), true, "earned it")

	// Four members, and the subject is not one of them: three have to agree.
	testing.SetRealm(testing.NewUserRealm(alice))
	Vote(cross(cur), id, true, "proposed it")
	testing.SetRealm(testing.NewUserRealm(bob))
	Vote(cross(cur), id, true, "agreed")
	uassert.Equal(t, "pending", board.Get(id).Status.String(), "two of four is not a majority")
	testing.SetRealm(testing.NewUserRealm(carol))
	Vote(cross(cur), id, true, "agreed")
	uassert.Equal(t, "completed", board.Get(id).Status.String(), "membership executes on approval")
	uassert.True(t, board.IsMember(zoe), "the board grew itself")
	uassert.Equal(t, 5, board.MemberCount())
}

// The verdict that would release a tranche the treasury cannot pay is refused
// outright, and changes nothing: no ballot, no release, no payment.
func TestReviewRefusesToReleaseWhatItCannotPay(cur realm, t *testing.T) {
	seed()
	urequire.Equal(t, int64(0), Balance(), "the seeded treasury is empty")

	g := board.Get(2)
	urequire.Equal(t, 1, len(g.Milestones[0].Current().Reviews), "the seed left one accept")

	// Four members and a majority of three, so the second accept is just a
	// ballot: it releases nothing and costs nothing.
	testing.SetRealm(testing.NewUserRealm(bob))
	Review(cross(cur), 2, 0, true, "merged, pay it")
	uassert.Equal(t, 2, len(g.Milestones[0].Current().Reviews))
	uassert.False(t, g.Milestones[0].Released)

	// The third one would release 1200 ugnot out of an empty treasury, so it
	// is refused outright and leaves no trace.
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, ErrUnderfunded.Error(), func() {
		Review(cross(cur), 2, 0, true, "same")
	})
	uassert.Equal(t, 2, len(g.Milestones[0].Current().Reviews), "the ballot was not recorded")
	uassert.False(t, g.Milestones[0].Released)
	uassert.Equal(t, 0, len(payments))
	uassert.Equal(t, int64(0), Disbursed())

	// The same member refusing costs the treasury nothing, so it records.
	testing.SetRealm(testing.NewUserRealm(carol))
	Review(cross(cur), 2, 0, false, "not convinced")
	uassert.Equal(t, 3, len(g.Milestones[0].Current().Reviews))
	uassert.Equal(t, "under review", g.Milestones[0].Current().Outcome.String())
}

// The whole path with real coins: fund, approve, prove, get paid, twice, and
// the treasury ends where it started.
func TestFullLifecyclePaysThroughTheBanker(cur realm, t *testing.T) {
	seed()
	urequire.Equal(t, int64(0), Balance(), "start from an empty treasury")

	// zoe asks for 500 in two tranches.
	testing.SetRealm(testing.NewUserRealm(zoe))
	id := Apply(cross(cur), "Ship the indexer", "two tranches", "alpha:100,beta:400")
	for _, m := range []address{alice, bob, carol} {
		testing.SetRealm(testing.NewUserRealm(m))
		Vote(cross(cur), id, true, "go")
	}
	urequire.Equal(t, "approved", board.Get(id).Status.String())
	uassert.Equal(t, int64(2500), Committed(), "the seeded grant plus this one")

	// eve funds the board, by name.
	fund(500)
	testing.SetOriginSend(chain.NewCoins(chain.NewCoin(Denom, 500)))
	testing.SetRealm(testing.NewUserRealm(eve))
	Fund(cross(cur))
	uassert.Equal(t, int64(500), Balance())
	uassert.Equal(t, int64(500), Raised())
	urequire.Equal(t, 1, len(donations))
	uassert.Equal(t, eve.String(), donations[0].From.String())

	// Milestone 1: proof, then the majority that carries it also pays it.
	testing.SetRealm(testing.NewUserRealm(zoe))
	SubmitProof(cross(cur), id, 0, "url", "https://example.com/pr/1", "alpha is live")
	testing.SetRealm(testing.NewUserRealm(alice))
	Review(cross(cur), id, 0, true, "confirmed")
	testing.SetRealm(testing.NewUserRealm(bob))
	Review(cross(cur), id, 0, true, "confirmed")
	uassert.Equal(t, int64(0), balanceOf(zoe), "two of four is not a majority yet")
	testing.SetRealm(testing.NewUserRealm(carol))
	Review(cross(cur), id, 0, true, "confirmed")

	uassert.Equal(t, int64(100), balanceOf(zoe), "the tranche landed")
	uassert.Equal(t, int64(400), Balance())
	uassert.Equal(t, int64(100), Disbursed())
	urequire.Equal(t, 1, len(payments))
	uassert.Equal(t, id, payments[0].Request)
	uassert.Equal(t, 0, payments[0].Milestone)
	uassert.Equal(t, int64(100), payments[0].Amount)
	uassert.Equal(t, "approved", board.Get(id).Status.String(), "one tranche to go")

	// Out of order is refused.
	testing.SetRealm(testing.NewUserRealm(zoe))
	uassert.AbortsContains(t, cur, grants.ErrOutOfOrder.Error(), func() {
		SubmitProof(cross(cur), id, 0, "url", "https://example.com/pr/1", "again")
	})

	// Milestone 2: a proof the board refuses, then one it accepts.
	testing.SetRealm(testing.NewUserRealm(zoe))
	SubmitProof(cross(cur), id, 1, "text", "trust me", "")
	for _, m := range []address{alice, bob, carol} {
		testing.SetRealm(testing.NewUserRealm(m))
		Review(cross(cur), id, 1, false, "no evidence")
	}
	uassert.Equal(t, int64(100), balanceOf(zoe), "a refused proof pays nothing")
	uassert.Equal(t, "approved", board.Get(id).Status.String(), "and does not kill the grant")

	testing.SetRealm(testing.NewUserRealm(zoe))
	SubmitProof(cross(cur), id, 1, "hash", "sha256:deadbeef", "beta, signed release")
	for _, m := range []address{alice, bob, carol} {
		testing.SetRealm(testing.NewUserRealm(m))
		Review(cross(cur), id, 1, true, "verified")
	}

	uassert.Equal(t, int64(500), balanceOf(zoe), "paid in full")
	uassert.Equal(t, "completed", board.Get(id).Status.String())
	uassert.Equal(t, int64(500), Disbursed())
	uassert.Equal(t, 2, len(payments))
	uassert.Equal(t, int64(0), Balance(), "the treasury is back to empty")
	uassert.Equal(t, int64(2000), Committed(), "only the seeded grant is still owed")

	// Both attempts on milestone 2 are on the record, refusal included.
	m2 := board.Get(id).Milestones[1]
	urequire.Equal(t, 2, len(m2.Attempts))
	uassert.Equal(t, "refused", m2.Attempts[0].Outcome.String())
	uassert.Equal(t, "no evidence", m2.Attempts[0].Reviews[0].Reason)
	uassert.Equal(t, "accepted", m2.Attempts[1].Outcome.String())
}

func TestFundRejectsAnEmptyTransfer(cur realm, t *testing.T) {
	seed()
	testing.SetOriginSend(chain.NewCoins())
	testing.SetRealm(testing.NewUserRealm(zoe))
	uassert.AbortsContains(t, cur, ErrNothingSent.Error(), func() { Fund(cross(cur)) })
	uassert.Equal(t, 0, len(donations))
}

func TestApplyRejectsABadMilestoneSpec(cur realm, t *testing.T) {
	seed()
	testing.SetRealm(testing.NewUserRealm(zoe))
	uassert.AbortsContains(t, cur, ErrBadSpec.Error(), func() {
		Apply(cross(cur), "Bad", "", "no amount here")
	})
	uassert.Equal(t, 3, board.Size(), "nothing was filed")
}

func TestRenderUnknownPaths(t *testing.T) {
	seed()
	uassert.True(t, len(Render("")) > 0)
	uassert.Equal(t, "# Grants DAO\n\nThere is no request 99.\n", Render("request/99"))
	uassert.Equal(t, "# Grants DAO\n\n`abc` is not a request number.\n", Render("request/abc"))
	uassert.True(t, len(Render("nope")) > 0)
}
