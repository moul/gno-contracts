package grants

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

// prog is the fixture: three members, and dave applying from outside, so a
// majority of the eligible set is two.
func prog() *Program { return NewProgram("ugnot", alice, bob, carol) }

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
		ms, err := ParseMilestones(tc.spec)
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
		_, err := ParseMilestones(bad)
		uassert.ErrorIs(t, err, ErrBadSpec, "should be rejected: "+bad)
	}
}

func TestFundRecordsTheDonor(t *testing.T) {
	p := prog()
	uassert.ErrorIs(t, p.Fund(dave, 0, 10), ErrNothingSent)
	uassert.ErrorIs(t, p.Fund(dave, -5, 10), ErrNothingSent)
	uassert.ErrorIs(t, p.Fund(address(""), 5, 10), ErrBadAddress)
	uassert.Equal(t, 0, len(p.Donations), "none of those were recorded")

	urequire.NoError(t, p.Fund(dave, 500, 10))
	urequire.NoError(t, p.Fund(mallory, 250, 11))
	urequire.Equal(t, 2, len(p.Donations))
	uassert.Equal(t, dave.String(), p.Donations[0].From.String())
	uassert.Equal(t, int64(500), p.Donations[0].Amount)
	uassert.Equal(t, int64(10), p.Donations[0].Height)
	uassert.Equal(t, int64(750), p.Raised())
}

func TestApplyGoesThroughTheSpec(t *testing.T) {
	p := prog()
	r, err := p.Apply(dave, "Ship it", "two tranches", "alpha:100,beta:400", 10)
	urequire.NoError(t, err)
	uassert.Equal(t, int64(500), r.Total())
	uassert.Equal(t, 2, len(r.Milestones))
	uassert.Equal(t, "beta", r.Milestones[1].Title)

	_, err = p.Apply(dave, "Bad", "", "no amount here", 10)
	uassert.ErrorIs(t, err, ErrBadSpec)
	uassert.Equal(t, 1, p.Board.Size(), "the bad one was never filed")
}

// Available is allowed to go negative. That is the whole reason Review takes
// a balance instead of trusting the board's own arithmetic.
func TestAvailableGoesNegativeWhenTheBoardOverPromises(t *testing.T) {
	p := prog()
	r, err := p.Apply(dave, "Ship it", "", "alpha:100,beta:400", 10)
	urequire.NoError(t, err)
	uassert.Equal(t, int64(0), p.Committed(), "pending promises nothing")
	uassert.Equal(t, int64(0), p.Available(0))

	urequire.NoError(t, errOf(p.Board.Vote(alice, r.ID, true, "", 11)))
	urequire.NoError(t, errOf(p.Board.Vote(bob, r.ID, true, "", 12)))
	uassert.Equal(t, int64(500), p.Committed())
	uassert.Equal(t, int64(-500), p.Available(0), "approved with an empty treasury")
	uassert.Equal(t, int64(100), p.Available(600))
}

func TestReviewRefusesTheVerdictItCannotPay(t *testing.T) {
	p := prog()
	r, err := p.Apply(dave, "Ship it", "", "alpha:100,beta:400", 10)
	urequire.NoError(t, err)
	urequire.NoError(t, errOf(p.Board.Vote(alice, r.ID, true, "", 11)))
	urequire.NoError(t, errOf(p.Board.Vote(bob, r.ID, true, "", 12)))
	urequire.NoError(t, p.Board.SubmitProof(dave, r.ID, 0, Proof{Kind: "url", Ref: "https://x/1", Height: 20}))

	// Not the deciding ballot, so the balance is irrelevant: it records.
	out, pay, err := p.Review(alice, r.ID, 0, true, "looks done", 21, 0)
	urequire.NoError(t, err)
	uassert.Equal(t, "under review", out.String())
	uassert.True(t, pay == nil, "nothing to pay yet")

	// The deciding ballot against an empty treasury changes nothing at all.
	out, pay, err = p.Review(bob, r.ID, 0, true, "agreed", 22, 99)
	uassert.ErrorIs(t, err, ErrUnderfunded)
	uassert.True(t, pay == nil)
	uassert.Equal(t, 1, len(r.Milestones[0].Current().Reviews), "the ballot was not recorded")
	uassert.False(t, r.Milestones[0].Released)
	uassert.Equal(t, 0, len(p.Payments))

	// A refusal from the same member costs the treasury nothing, so it lands,
	// even against a balance of zero. It does not settle anything on its own:
	// alice already accepted, so this is one all against a bar of two.
	out, pay, err = p.Review(bob, r.ID, 0, false, "not convinced", 23, 0)
	urequire.NoError(t, err)
	uassert.Equal(t, "under review", out.String())
	uassert.True(t, pay == nil)
	uassert.Equal(t, 2, len(r.Milestones[0].Current().Reviews), "this one WAS recorded")

	// The second refusal reaches the bar and closes the attempt, still with
	// an empty treasury, because refusing costs nothing.
	out, pay, err = p.Review(carol, r.ID, 0, false, "same", 24, 0)
	urequire.NoError(t, err)
	uassert.Equal(t, "refused", out.String())
	uassert.True(t, pay == nil)
	uassert.False(t, r.Milestones[0].Released)
	uassert.Equal(t, "approved", r.Status.String(), "a refused proof does not kill the grant")
}

func TestReviewHandsBackThePaymentToExecute(t *testing.T) {
	p := prog()
	r, err := p.Apply(dave, "Ship it", "", "alpha:100,beta:400", 10)
	urequire.NoError(t, err)
	urequire.NoError(t, errOf(p.Board.Vote(alice, r.ID, true, "", 11)))
	urequire.NoError(t, errOf(p.Board.Vote(bob, r.ID, true, "", 12)))

	urequire.NoError(t, p.Board.SubmitProof(dave, r.ID, 0, Proof{Kind: "url", Ref: "https://x/1", Height: 20}))
	urequire.NoError(t, errOf3(p.Review(alice, r.ID, 0, true, "", 21, 500)))
	out, pay, err := p.Review(carol, r.ID, 0, true, "", 22, 500)
	urequire.NoError(t, err)
	uassert.Equal(t, "accepted", out.String())
	urequire.True(t, pay != nil, "the caller is handed a payment to execute")
	uassert.Equal(t, dave.String(), pay.To.String())
	uassert.Equal(t, int64(100), pay.Amount)
	uassert.Equal(t, r.ID, pay.Request)
	uassert.Equal(t, 0, pay.Milestone)
	uassert.Equal(t, int64(22), pay.Height)

	urequire.Equal(t, 1, len(p.Payments), "and it is on the ledger")
	uassert.Equal(t, int64(100), p.Disbursed())
	uassert.Equal(t, int64(400), p.Committed())
	uassert.Equal(t, int64(300), p.Available(700))

	// Second tranche completes it.
	urequire.NoError(t, p.Board.SubmitProof(dave, r.ID, 1, Proof{Kind: "hash", Ref: "deadbeef", Height: 30}))
	urequire.NoError(t, errOf3(p.Review(alice, r.ID, 1, true, "", 31, 400)))
	out, pay, err = p.Review(bob, r.ID, 1, true, "", 32, 400)
	urequire.NoError(t, err)
	uassert.Equal(t, "accepted", out.String())
	urequire.True(t, pay != nil)
	uassert.Equal(t, int64(400), pay.Amount)
	uassert.Equal(t, "completed", r.Status.String())
	uassert.Equal(t, int64(500), p.Disbursed())
	uassert.Equal(t, int64(0), p.Committed())
	uassert.Equal(t, 2, len(p.Payments))
}

// A one-member program is a legitimate configuration (it is what a personal
// board is), and its majority is one. It still cannot self-grant.
func TestOneMemberBoard(t *testing.T) {
	p := NewProgram("ugnot", alice)
	r, err := p.Apply(dave, "Ship it", "", "alpha:100", 10)
	urequire.NoError(t, err)
	uassert.Equal(t, 1, p.Board.Eligible(r))
	uassert.Equal(t, 1, p.Board.Majority(r))
	st, err := p.Board.Vote(alice, r.ID, true, "sure", 11)
	urequire.NoError(t, err)
	uassert.Equal(t, "approved", st.String(), "one signature carries a one-member board")

	own, err := p.Apply(alice, "Pay myself", "", "alpha:100", 12)
	urequire.NoError(t, err)
	uassert.Equal(t, 0, p.Board.Eligible(own), "the applicant is the whole board")
	uassert.Equal(t, 1, p.Board.Majority(own), "so the bar is unreachable, not zero")
	uassert.ErrorIs(t, errOf(p.Board.Vote(alice, own.ID, true, "", 13)), ErrConflict)
	uassert.Equal(t, "pending", own.Status.String(), "a sole member cannot self-grant")
}

func errOf3(_ Outcome, _ *Payment, err error) error { return err }

func TestTheTrancheGoesToTheBeneficiary(t *testing.T) {
	p := NewProgram("ugnot", alice, bob)
	r, err := p.ApplyFor(dave, mallory, "mallory cannot pay the gas to ask", "t", "", "one:700", 10)
	urequire.NoError(t, err)
	p.Board.Vote(alice, r.ID, true, "", 11)
	p.Board.Vote(bob, r.ID, true, "", 12)
	urequire.NoError(t, p.Board.SubmitProof(dave, r.ID, 0, Proof{Kind: "text", Ref: "done", Height: 13}))

	_, pay, err := p.Review(alice, r.ID, 0, true, "", 14, 700)
	urequire.NoError(t, err)
	uassert.True(t, pay == nil, "neither party sits on the board, so both members must accept")

	_, pay, err = p.Review(bob, r.ID, 0, true, "", 15, 700)
	urequire.NoError(t, err)
	urequire.True(t, pay != nil, "the second accept releases it")
	uassert.Equal(t, mallory.String(), pay.To.String(), "the money goes to the payee, not the filer")
	uassert.Equal(t, int64(700), pay.Amount)
	uassert.Equal(t, mallory.String(), p.Payments[0].To.String(), "and so does the ledger row")
}
