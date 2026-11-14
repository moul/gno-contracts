package govgrant

import (
	"errors"
	"strconv"
	"strings"

	"chain"
	"chain/banker"
	"chain/runtime"

	"gno.land/p/moul/grants/v1"
	"gno.land/p/moul/kit/ui/v0"
	"gno.land/r/gov/dao"
)

// The four levers GovDAO holds over this board. Each New*Request builds a
// GovDAO proposal; the change happens only when r/gov/dao executes it after an
// accepted vote. Create one from a `gnokey maketx run` script:
//
//	dao.MustCreateProposal(cross(cur), govgrant.NewSetBoardRequest(cross(cur), members, reason))
//
// Arguments are checked when the request is BUILT, so a bad one fails in the
// proposer's own transaction instead of after the vote. The reason is
// required and printed in the proposal, because it is what voters read.

var errNotGovDAO = errors.New("govgrant: only GovDAO may pull this lever")

// NewSetBoardRequest replaces the board with members. A member who stays
// keeps their seniority; ballots of one who leaves stop counting.
//
//gnovet:ignore uncallable-crossing-arg built inside a MsgRun proposal script only; its ProposalRequest result is unusable from a MsgCall anyway
func NewSetBoardRequest(cur realm, members []address, reason string) dao.ProposalRequest {
	reason = mustReason(reason)
	if err := grants.New().SetMembers(0, members...); err != nil {
		panic(err)
	}
	list := make([]string, len(members))
	for i, m := range members {
		list[i] = m.String()
	}
	return request(cur, "seat the grant board",
		"Replace the members of the grant board at "+Path+" with: "+strings.Join(list, ", ")+
			". A grant then needs a majority of these members, the applicant excluded.",
		reason,
		func(realm) error { return setBoard(members) })
}

// NewSetCapRequest sets the most one request may ask for, in ugnot; 0 removes
// the cap. Grants already filed are not affected.
func NewSetCapRequest(cur realm, cap int64, reason string) dao.ProposalRequest {
	reason = mustReason(reason)
	if cap < 0 {
		panic(grants.ErrBadCap)
	}
	return request(cur, "set the grant cap",
		"Set the most one grant request at "+Path+" may ask for to "+
			strconv.FormatInt(cap, 10)+" "+Denom+" (0 means no cap).",
		reason,
		func(realm) error { return setCap(cap) })
}

// NewSetPausedRequest stops or restarts payouts. Filing, voting and refusing
// proofs carry on while paused; only a verdict that would pay is refused.
func NewSetPausedRequest(cur realm, paused bool, reason string) dao.ProposalRequest {
	reason = mustReason(reason)
	what := "Resume payouts from"
	if paused {
		what = "Pause every payout from"
	}
	return request(cur, "pause or resume grant payouts", what+" the grant board at "+Path+".",
		reason,
		func(realm) error { setPaused(paused); return nil })
}

// NewSweepRequest sends amount ugnot from the board's treasury to to: unspent
// budget back to GovDAO's treasury, or a board wound down. It may take money
// already promised to approved grants; the proposal says how much that is at
// the time it is built.
func NewSweepRequest(cur realm, to address, amount int64, reason string) dao.ProposalRequest {
	reason = mustReason(reason)
	if amount <= 0 {
		panic(grants.ErrNothingSent)
	}
	if !to.IsValid() {
		panic(grants.ErrBadAddress)
	}
	return request(cur, "return grant money",
		"Send "+strconv.FormatInt(amount, 10)+" "+Denom+" from the grant board at "+Path+
			" to "+to.String()+". At proposal time the board held "+strconv.FormatInt(Balance(), 10)+
			" and had promised "+strconv.FormatInt(Committed(), 10)+" to approved grants.",
		reason,
		func(cur realm) error { return sweep(cur, to, amount) })
}

func mustReason(reason string) string {
	reason = strings.TrimSpace(reason)
	if ui.Inline(reason) == "" {
		panic("govgrant: a GovDAO request needs a reason")
	}
	if len(reason) > grants.MaxReason {
		panic(grants.ErrBadReason)
	}
	return reason
}

// request wraps a lever in a GovDAO proposal whose callback runs it only when
// r/gov/dao is the caller. The executor already refuses anyone else; govern
// checks again so the guarantee lives here and not only upstream.
//
// audit-pattern callback_param: request and govern are unexported, and every
// fn they take is a literal written in this file; no caller can supply one.
func request(cur realm, title, what, reason string, fn func(realm) error) dao.ProposalRequest {
	cb := func(cur realm) error { return govern(cur, fn) }
	desc := what + "\n\nReason: " + reason
	e := dao.NewSimpleExecutor(0, cur, cb, desc)
	return dao.NewProposalRequest("govgrant: "+title, desc, e)
}

// govern runs fn with the callback's own live cur, which the sweep lever needs
// for the banker, after checking the frame was entered from r/gov/dao.
func govern(cur realm, fn func(realm) error) error {
	if !cur.IsCurrent() {
		return errNotGovDAO
	}
	if cur.Previous().PkgPath() != GovDAO {
		return errNotGovDAO
	}
	return fn(cur)
}

// The lever bodies. Unexported: the only way to reach them on chain is an
// executed GovDAO proposal.

func setBoard(members []address) error {
	if err := program.Board.SetMembers(runtime.ChainHeight(), members...); err != nil {
		return err
	}
	list := make([]string, 0, len(members))
	for _, m := range program.Board.Members() {
		list = append(list, m.String())
	}
	chain.Emit("SetBoard", "members", strings.Join(list, ","))
	return nil
}

func setCap(cap int64) error {
	if err := program.SetCap(cap); err != nil {
		return err
	}
	chain.Emit("SetCap", "cap", strconv.FormatInt(cap, 10))
	return nil
}

func setPaused(paused bool) {
	program.Paused = paused
	chain.Emit("SetPaused", "paused", strconv.FormatBool(paused))
}

func sweep(cur realm, to address, amount int64) error {
	s, err := program.Sweep(to, amount, runtime.ChainHeight(), Balance())
	if err != nil {
		return err
	}
	banker.NewBanker(banker.BankerTypeRealmSend, cur).
		SendCoins(Address(), s.To, chain.NewCoins(chain.NewCoin(Denom, s.Amount)))
	chain.Emit("Sweep", "to", s.To.String(), "amount", strconv.FormatInt(s.Amount, 10))
	return nil
}
