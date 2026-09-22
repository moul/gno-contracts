package grant

import (
	"chain"
	"chain/banker"
	"testing"

	"gno.land/p/moul/grants/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

const (
	zoe = address("g12cs4cehujpffpjpywmkqj43m6u5ya53nj69sjz") // an applicant
	kim = address("g1jvh5ukk07dvd57fxefcp5aa29xaydxmxs7myyp") // a second one
)

func balanceOf(a address) int64 {
	return banker.NewReadonlyBanker().GetCoins(a).AmountOf(Denom)
}

func issue(n int64) { testing.IssueCoins(Address(), chain.NewCoins(chain.NewCoin(Denom, n))) }

func TestFreshBoardIsOwnedAndEmpty(t *testing.T) {
	reset()
	uassert.True(t, Owner.IsValid(), "the owner is a real address")
	uassert.True(t, zoe.IsValid())
	uassert.True(t, kim.IsValid())
	uassert.True(t, Address().IsValid(), "the treasury address")

	urequire.Equal(t, 1, len(Members()))
	uassert.Equal(t, Owner.String(), Members()[0].String())
	uassert.Equal(t, 0, Requests(), "nothing seeded, this board is real")
	uassert.Equal(t, int64(0), Committed())
	uassert.Equal(t, int64(0), Raised())
	uassert.Equal(t, int64(0), Disbursed())
}

// The whole path with real coins, on a one-member board: the owner is the
// majority, so one ballot carries and one review pays.
func TestApplyApproveProveGetPaid(cur realm, t *testing.T) {
	reset()
	urequire.Equal(t, int64(0), Balance(), "start from an empty treasury")

	// Someone funds the board, by name.
	issue(500)
	testing.SetOriginSend(chain.NewCoins(chain.NewCoin(Denom, 500)))
	testing.SetRealm(testing.NewUserRealm(kim))
	Fund(cross(cur))
	uassert.Equal(t, int64(500), Balance())
	uassert.Equal(t, int64(500), Raised())
	uassert.Equal(t, kim.String(), program.Donations[0].From.String())

	// An outsider applies. Anyone may.
	testing.SetRealm(testing.NewUserRealm(zoe))
	id := Apply(cross(cur), "Ship the indexer", "two tranches", "alpha:100,beta:400")
	uassert.Equal(t, 1, id)
	uassert.Equal(t, int64(0), Committed(), "a pending request promises nothing")

	// A non-member cannot vote, not even the applicant.
	testing.SetRealm(testing.NewUserRealm(zoe))
	uassert.AbortsContains(t, cur, grants.ErrNotMember.Error(), func() {
		Vote(cross(cur), id, true, "me again")
	})

	testing.SetRealm(testing.NewUserRealm(Owner))
	Vote(cross(cur), id, true, "worth it")
	uassert.Equal(t, int64(500), Committed(), "approval promises the full ask")
	uassert.Equal(t, int64(0), Available())

	// Milestone 1: proof, then the one review that carries also pays.
	testing.SetRealm(testing.NewUserRealm(kim))
	uassert.AbortsContains(t, cur, grants.ErrNotApplicant.Error(), func() {
		SubmitProof(cross(cur), id, 0, "url", "https://example.com/pr/1", "not mine to prove")
	})
	testing.SetRealm(testing.NewUserRealm(zoe))
	SubmitProof(cross(cur), id, 0, "url", "https://example.com/pr/1", "alpha is live")
	testing.SetRealm(testing.NewUserRealm(Owner))
	Review(cross(cur), id, 0, true, "confirmed")

	uassert.Equal(t, int64(100), balanceOf(zoe), "the tranche landed")
	uassert.Equal(t, int64(400), Balance())
	uassert.Equal(t, int64(100), Disbursed())
	urequire.Equal(t, 1, len(program.Payments))
	uassert.Equal(t, int64(100), program.Payments[0].Amount)

	// Out of order is refused.
	testing.SetRealm(testing.NewUserRealm(zoe))
	uassert.AbortsContains(t, cur, grants.ErrOutOfOrder.Error(), func() {
		SubmitProof(cross(cur), id, 0, "url", "https://example.com/pr/1", "again")
	})

	// Milestone 2: a proof the owner refuses, then one they accept.
	testing.SetRealm(testing.NewUserRealm(zoe))
	SubmitProof(cross(cur), id, 1, "text", "trust me", "")
	testing.SetRealm(testing.NewUserRealm(Owner))
	Review(cross(cur), id, 1, false, "no evidence")
	uassert.Equal(t, int64(100), balanceOf(zoe), "a refused proof pays nothing")

	testing.SetRealm(testing.NewUserRealm(zoe))
	SubmitProof(cross(cur), id, 1, "hash", "sha256:deadbeef", "beta, signed release")
	testing.SetRealm(testing.NewUserRealm(Owner))
	Review(cross(cur), id, 1, true, "verified")

	uassert.Equal(t, int64(500), balanceOf(zoe), "paid in full")
	uassert.Equal(t, int64(0), Balance(), "the treasury is back to empty")
	uassert.Equal(t, int64(0), Committed())
	uassert.Equal(t, int64(500), Disbursed())
	uassert.Equal(t, 2, len(program.Payments))

	// Both attempts on milestone 2 are on the record, refusal included.
	m2 := program.Board.Get(id).Milestones[1]
	urequire.Equal(t, 2, len(m2.Attempts))
	uassert.Equal(t, "refused", m2.Attempts[0].Outcome.String())
	uassert.Equal(t, "no evidence", m2.Attempts[0].Reviews[0].Reason)
	uassert.Equal(t, "accepted", m2.Attempts[1].Outcome.String())
}

// The verdict that would release a tranche the treasury cannot pay is refused
// outright and leaves no trace.
func TestReviewRefusesToReleaseWhatItCannotPay(cur realm, t *testing.T) {
	reset()
	urequire.Equal(t, int64(0), Balance(), "no coins anywhere")

	testing.SetRealm(testing.NewUserRealm(zoe))
	id := Apply(cross(cur), "Ship the indexer", "", "alpha:100")
	testing.SetRealm(testing.NewUserRealm(Owner))
	Vote(cross(cur), id, true, "worth it")
	testing.SetRealm(testing.NewUserRealm(zoe))
	SubmitProof(cross(cur), id, 0, "url", "https://example.com/pr/1", "")

	testing.SetRealm(testing.NewUserRealm(Owner))
	uassert.AbortsContains(t, cur, grants.ErrUnderfunded.Error(), func() {
		Review(cross(cur), id, 0, true, "confirmed")
	})
	m := program.Board.Get(id).Milestones[0]
	uassert.Equal(t, 0, len(m.Current().Reviews), "the ballot was not recorded")
	uassert.False(t, m.Released)
	uassert.Equal(t, 0, len(program.Payments))
	uassert.Equal(t, int64(-100), Available(), "and the shortfall is visible")
}

func TestRetractAndBadInput(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(zoe))
	uassert.AbortsContains(t, cur, grants.ErrBadSpec.Error(), func() {
		Apply(cross(cur), "Bad", "", "no amount here")
	})
	uassert.Equal(t, 0, Requests(), "nothing was filed")

	testing.SetRealm(testing.NewUserRealm(zoe))
	id := Apply(cross(cur), "Never mind", "", "thing:1")
	testing.SetRealm(testing.NewUserRealm(kim))
	uassert.AbortsContains(t, cur, grants.ErrNotApplicant.Error(), func() {
		Retract(cross(cur), id)
	})
	testing.SetRealm(testing.NewUserRealm(zoe))
	Retract(cross(cur), id)
	uassert.Equal(t, "withdrawn", program.Board.Get(id).Status.String())

	testing.SetOriginSend(chain.NewCoins())
	testing.SetRealm(testing.NewUserRealm(kim))
	uassert.AbortsContains(t, cur, grants.ErrNothingSent.Error(), func() { Fund(cross(cur)) })
	uassert.Equal(t, 0, len(program.Donations))
}

// The owner can hand out a seat, and once there are two members the bar moves
// to two. That is the path from this personal board to a real one.
func TestProposeMemberGrowsTheBoardAndRaisesTheBar(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(zoe))
	uassert.AbortsContains(t, cur, grants.ErrNotMember.Error(), func() {
		ProposeMember(cross(cur), zoe.String(), true, "let me in")
	})

	testing.SetRealm(testing.NewUserRealm(Owner))
	id := ProposeMember(cross(cur), kim.String(), true, "reviews everything anyway")
	testing.SetRealm(testing.NewUserRealm(Owner))
	Vote(cross(cur), id, true, "proposed it")
	uassert.Equal(t, "completed", program.Board.Get(id).Status.String())
	urequire.Equal(t, 2, len(Members()))

	testing.SetRealm(testing.NewUserRealm(zoe))
	next := Apply(cross(cur), "Ship the indexer", "", "alpha:100")
	r := program.Board.Get(next)
	uassert.Equal(t, 2, program.Board.Eligible(r))
	uassert.Equal(t, 2, program.Board.Majority(r), "two members, two signatures")

	testing.SetRealm(testing.NewUserRealm(Owner))
	Vote(cross(cur), next, true, "worth it")
	uassert.Equal(t, "pending", program.Board.Get(next).Status.String(), "the owner is no longer a majority")
	testing.SetRealm(testing.NewUserRealm(kim))
	Vote(cross(cur), next, true, "agreed")
	uassert.Equal(t, "approved", program.Board.Get(next).Status.String())
}

func TestRenderUnknownPaths(t *testing.T) {
	reset()
	uassert.True(t, len(Render("")) > 0)
	uassert.Equal(t, "# moul's grant board\n\nThere is no request 99.\n", Render("request/99"))
	uassert.True(t, len(Render("ledger")) > 0)
	uassert.True(t, len(Render("nope")) > 0)
}

// The case this board exists for: an account with nothing in it cannot pay the
// gas to ask for its first coins, so someone else asks for it. The treasury
// ends where it started, at zero, which is what the pinned pages render.
func TestApplyForPaysTheBeneficiaryNotTheFiler(cur realm, t *testing.T) {
	reset()
	urequire.Equal(t, int64(0), Balance())
	before := balanceOf(kim)

	issue(300)
	testing.SetOriginSend(chain.NewCoins(chain.NewCoin(Denom, 300)))
	testing.SetRealm(testing.NewUserRealm(address(Owner)))
	Fund(cross(cur))

	// zoe files for kim, whose account is empty.
	testing.SetRealm(testing.NewUserRealm(zoe))
	id := ApplyFor(cross(cur), kim.String(), "kim's account is empty, she cannot pay the gas",
		"Fund a first key", "so she can transact at all", "first transfer:300")
	r := program.Board.Get(id)
	urequire.True(t, r.OnBehalf())
	uassert.Equal(t, kim.String(), r.Payee().String())

	// The owner carries it alone, and either party may prove it. Here the
	// filer does, because the payee still cannot send a transaction.
	testing.SetRealm(testing.NewUserRealm(address(Owner)))
	Vote(cross(cur), id, true, "I know kim.")
	testing.SetRealm(testing.NewUserRealm(zoe))
	SubmitProof(cross(cur), id, 0, "text", "she has a key and no coins", "")
	testing.SetRealm(testing.NewUserRealm(address(Owner)))
	Review(cross(cur), id, 0, true, "Sent.")

	uassert.Equal(t, before+300, balanceOf(kim), "the payee got the coins")
	uassert.Equal(t, int64(0), Balance(), "and the treasury is back to empty")
	uassert.Equal(t, kim.String(), program.Payments[0].To.String())

	// A reason is not optional when the payee is someone else.
	testing.SetRealm(testing.NewUserRealm(zoe))
	uassert.AbortsContains(t, cur, "needs a reason", func() {
		ApplyFor(cross(cur), kim.String(), "", "no reason given", "", "x:1")
	})
}
