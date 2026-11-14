package govgrant

import (
	"chain"
	"chain/banker"
	"testing"

	"gno.land/p/moul/grants/v1"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

const (
	ana  = address("g1v9kxjcm9ta047h6lta047h6lta047h6lzd40gh") // a member
	ben  = address("g1vfhkyh6lta047h6lta047h6lta047h6l03vdhu") // a member
	zoe  = address("g12cs4cehujpffpjpywmkqj43m6u5ya53nj69sjz") // an applicant
	kim  = address("g1jvh5ukk07dvd57fxefcp5aa29xaydxmxs7myyp") // a second one
)

func balanceOf(a address) int64 {
	return banker.NewReadonlyBanker().GetCoins(a).AmountOf(Denom)
}

func issue(n int64) { testing.IssueCoins(Address(), chain.NewCoins(chain.NewCoin(Denom, n))) }

// seated is a fresh board with ana and ben on it, as the first GovDAO
// proposal would leave it.
func seated(t *testing.T) {
	t.Helper()
	reset()
	urequire.NoError(t, setBoard([]address{ana, ben}))
}

// Deployed, the board has nobody on it, so nothing can be decided and nothing
// can leave until GovDAO seats someone. That is the safe default for a realm
// a DAO is about to fund.
func TestFreshBoardIsInert(cur realm, t *testing.T) {
	reset()
	uassert.Equal(t, 0, len(Members()))
	uassert.Equal(t, DefaultCap, Cap())
	uassert.False(t, Paused())
	uassert.Equal(t, 0, Requests())

	testing.SetRealm(testing.NewUserRealm(zoe))
	id := Apply(cross(cur), "Ship the indexer", "", "alpha:100")
	testing.SetRealm(testing.NewUserRealm(ana))
	uassert.AbortsContains(t, cur, grants.ErrNotMember.Error(), func() {
		Vote(cross(cur), id, true, "")
	})
	uassert.AbortsContains(t, cur, grants.ErrNotMember.Error(), func() {
		ProposeMember(cross(cur), ana.String(), true, "")
	})
}

// The whole path on a two-member funded board: an outsider
// asks, both approve, a proof, both accept, the tranche is paid.
func TestTwoMemberBoardPaysOnBothSignatures(cur realm, t *testing.T) {
	seated(t)
	issue(500)
	before := balanceOf(zoe)

	testing.SetRealm(testing.NewUserRealm(zoe))
	id := Apply(cross(cur), "Ship the indexer", "", "alpha:500")

	testing.SetRealm(testing.NewUserRealm(ana))
	Vote(cross(cur), id, true, "worth it")
	uassert.Equal(t, "pending", program.Board.Get(id).Status.String(), "one of two is not a majority")
	testing.SetRealm(testing.NewUserRealm(ben))
	Vote(cross(cur), id, true, "agreed")
	uassert.Equal(t, "approved", program.Board.Get(id).Status.String())

	testing.SetRealm(testing.NewUserRealm(zoe))
	SubmitProof(cross(cur), id, 0, "url", "https://example.com/pr/1", "")
	testing.SetRealm(testing.NewUserRealm(ana))
	Review(cross(cur), id, 0, true, "confirmed")
	uassert.Equal(t, before, balanceOf(zoe), "one review of two pays nothing")
	testing.SetRealm(testing.NewUserRealm(ben))
	Review(cross(cur), id, 0, true, "confirmed")

	uassert.Equal(t, before+500, balanceOf(zoe))
	uassert.Equal(t, int64(0), Balance())
	uassert.Equal(t, int64(500), Disbursed())
}

// The capture the library fix closes, driven through the realm: on a board
// of two, neither member can remove the other and then spend alone.
func TestOneMemberCannotTakeTheBoard(cur realm, t *testing.T) {
	seated(t)
	testing.SetRealm(testing.NewUserRealm(ana))
	uassert.AbortsContains(t, cur, grants.ErrBoardTooSmall.Error(), func() {
		ProposeMember(cross(cur), ben.String(), false, "goodbye")
	})
	urequire.Equal(t, 2, len(Members()))
}

func TestCapIsEnforcedAtFiling(cur realm, t *testing.T) {
	seated(t)
	urequire.NoError(t, setCap(1000))

	testing.SetRealm(testing.NewUserRealm(zoe))
	uassert.AbortsContains(t, cur, grants.ErrOverCap.Error(), func() {
		Apply(cross(cur), "Too big", "", "a:600,b:401")
	})
	uassert.AbortsContains(t, cur, grants.ErrOverCap.Error(), func() {
		ApplyFor(cross(cur), kim.String(), "empty account", "Too big", "", "a:1001")
	})
	uassert.Equal(t, 0, Requests())
	Apply(cross(cur), "Fits", "", "a:600,b:400")
	uassert.Equal(t, 1, Requests())

	uassert.Error(t, setCap(-1))
	uassert.Equal(t, int64(1000), Cap(), "a refused cap changes nothing")
}

func TestPauseStopsPayoutsNotTheRecord(cur realm, t *testing.T) {
	seated(t)
	issue(100)

	testing.SetRealm(testing.NewUserRealm(zoe))
	id := Apply(cross(cur), "Ship", "", "a:100")
	testing.SetRealm(testing.NewUserRealm(ana))
	Vote(cross(cur), id, true, "")
	testing.SetRealm(testing.NewUserRealm(ben))
	Vote(cross(cur), id, true, "")
	testing.SetRealm(testing.NewUserRealm(zoe))
	SubmitProof(cross(cur), id, 0, "url", "https://example.com/pr/1", "")

	setPaused(true)
	testing.SetRealm(testing.NewUserRealm(ana))
	Review(cross(cur), id, 0, true, "fine")
	testing.SetRealm(testing.NewUserRealm(ben))
	uassert.AbortsContains(t, cur, grants.ErrPaused.Error(), func() {
		Review(cross(cur), id, 0, true, "fine")
	})
	uassert.Equal(t, int64(100), Balance(), "nothing left while paused")

	setPaused(false)
	testing.SetRealm(testing.NewUserRealm(ben))
	Review(cross(cur), id, 0, true, "fine")
	uassert.Equal(t, int64(0), Balance())
}

func TestSetBoardReplacesTheMembers(t *testing.T) {
	seated(t)
	uassert.Error(t, setBoard(nil), "an empty board is refused")
	uassert.Error(t, setBoard([]address{address("nope")}))
	urequire.Equal(t, 2, len(Members()), "a refused call changes nothing")

	urequire.NoError(t, setBoard([]address{kim}))
	urequire.Equal(t, 1, len(Members()))
	uassert.Equal(t, kim.String(), Members()[0].String())
}

func TestSweepSendsAndRecords(cur realm, t *testing.T) {
	seated(t)
	issue(700)
	before := balanceOf(kim)

	uassert.Error(t, sweep(cur, kim, 701), "more than the balance")
	uassert.Error(t, sweep(cur, kim, 0))
	urequire.NoError(t, sweep(cur, kim, 700))

	uassert.Equal(t, before+700, balanceOf(kim))
	uassert.Equal(t, int64(0), Balance())
	uassert.Equal(t, int64(700), Swept())
	uassert.Equal(t, int64(0), Disbursed(), "a sweep is not a grant")
}

// Building a proposal checks its arguments up front, so a bad one fails in
// the proposer's transaction and never reaches a vote.
func TestRequestsRefuseBadArgumentsBeforeTheVote(cur realm, t *testing.T) {
	reset()
	uassert.AbortsContains(t, cur, grants.ErrNoMembers.Error(), func() {
		NewSetBoardRequest(cross(cur), nil, "x")
	})
	uassert.AbortsContains(t, cur, grants.ErrBadCap.Error(), func() {
		NewSetCapRequest(cross(cur), -5, "x")
	})
	uassert.AbortsContains(t, cur, grants.ErrNothingSent.Error(), func() {
		NewSweepRequest(cross(cur), kim, 0, "x")
	})
	uassert.AbortsContains(t, cur, "needs a reason", func() {
		NewSetPausedRequest(cross(cur), true, "  ")
	})

	r := NewSetBoardRequest(cross(cur), []address{ana, ben}, "two reviewers for the first round")
	uassert.Equal(t, "govgrant: seat the grant board", r.Title())
	uassert.True(t, len(r.Description()) > 0)
	uassert.Equal(t, 0, len(Members()), "building a request changes nothing")
}

// A realm that is not GovDAO cannot reach a lever: the executor refuses to run
// for anyone but r/gov/dao, and no exported function exposes the callbacks.
func TestRequestExecutorRefusesAnyoneButGovDAO(cur realm, t *testing.T) {
	reset()
	uassert.ErrorContains(t, govern(cur, func(realm) error { return setBoard([]address{zoe}) }), "only GovDAO")
	uassert.Equal(t, 0, len(Members()))
}

func TestRenderUnknownPaths(t *testing.T) {
	reset()
	uassert.True(t, len(Render("")) > 0)
	uassert.True(t, len(Render("ledger")) > 0)
	uassert.True(t, len(Render("nope")) > 0)
}
