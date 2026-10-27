// Package govgrant is a grant board that GovDAO funds and GovDAO governs.
//
// GovDAO sends the treasury money once, a small board of members decides
// grants out of it, and every tranche leaves only on a majority of that
// board. Each grant is NOT its own GovDAO proposal: that design, a proposal
// factory, puts a DAO vote in front of every payout.
//
// # Who decides what
//
// Anyone may Apply, ApplyFor someone else, Retract their own pending request
// and SubmitProof for their own approved grant. Members Vote on requests,
// Review proofs and ProposeMember changes; all of that is the library's rules,
// unchanged, including that the party a decision is about never votes on it.
//
// GovDAO, and only GovDAO, holds four levers, each one a proposal its members
// vote on: who sits on the board (NewSetBoardRequest), the most one request
// may ask for (NewSetCapRequest), whether payouts are paused
// (NewSetPausedRequest), and taking money back out (NewSweepRequest). A
// lever's callback runs only when r/gov/dao executes an accepted proposal.
//
// Deployed, the board has NO members. Nothing can be decided and nothing can
// leave until GovDAO seats someone, so the realm is safe to fund before it is
// staffed and safe to deploy before it is funded.
//
// # Why this is a separate realm
//
// gno.land/r/moul/grant/v0 is moul's own pocket money, says so on its page,
// and is private: its creator can redeploy it with the coins kept and the code
// replaced. That is fine for one person's money and wrong for a DAO's, so this
// realm is public and its code can never change. Every rule lives in
// gno.land/p/moul/grants/v1; this file is the chain-facing glue.
package govgrant

import (
	"strconv"

	"chain"
	"chain/banker"
	"chain/runtime"
	"chain/runtime/unsafe"

	"gno.land/p/moul/grants/v1"
)

const (
	// Denom is the only coin this board holds or pays.
	Denom = "ugnot"
	// Path is this realm's package path; its treasury is derived from it.
	Path = "gno.land/r/moul/govgrant/v0"
	// Link is Path as a gnoweb route.
	Link = "/r/moul/govgrant/v0"
	// GovDAO is the only realm whose executed proposals may pull a lever.
	GovDAO = "gno.land/r/gov/dao"
	// DefaultCap is the most one request may ask for until GovDAO says
	// otherwise: 50 GNOT. Deliberately low, and GovDAO can raise it.
	DefaultCap = int64(50_000_000)
)

var program *grants.Program

func init() { reset() }

// reset installs a fresh board with no members and the default cap. Also
// called by the tests, since realm globals persist across a test binary.
func reset() {
	program = grants.NewProgram(Denom)
	program.Cap = DefaultCap
}

// Address is the treasury: this realm's own package address.
func Address() address { return chain.PackageAddress(Path) }

// Balance is what the treasury actually holds.
func Balance() int64 {
	return banker.NewReadonlyBanker().GetCoins(Address()).AmountOf(Denom)
}

// Committed is what approved grants can still claim; Available is the
// balance minus that, and can go negative. See the library for why.
func Committed() int64 { return program.Committed() }
func Available() int64 { return program.Available(Balance()) }

// Raised is what was donated through Fund. GovDAO's own payment arrives as a
// plain transfer and is on the GovDAO treasury's history, not here.
func Raised() int64    { return program.Raised() }
func Disbursed() int64 { return program.Disbursed() }
func Swept() int64     { return program.Swept() }

// Cap is the most one request may ask for, in ugnot; 0 means no cap.
func Cap() int64   { return program.Cap }
func Paused() bool { return program.Paused }

// Members lists the board.
func Members() []address { return program.Board.Members() }

// Requests is how many requests have ever been filed.
func Requests() int { return program.Board.Size() }

// Fund credits the ugnot sent with the call to the treasury and puts the donor
// on the record. Only a direct user call may read OriginSend: a realm in
// between keeps the coins and could book the same send as many donations.
func Fund(cur realm) {
	if !cur.IsCurrent() {
		panic("govgrant: spoofed realm")
	}
	prev := cur.Previous()
	if !prev.IsUserCall() {
		panic("govgrant: Fund must be called directly by an account, with -send")
	}
	from := prev.Address()
	amount := unsafe.OriginSend().AmountOf(Denom)
	if err := program.Fund(from, amount, runtime.ChainHeight()); err != nil {
		panic(err)
	}
	chain.Emit("Fund", "from", from.String(), "amount", strconv.FormatInt(amount, 10))
}

// Apply files a grant request for the caller. milestones reads
// "title:amount,title:amount", amounts in ugnot, paid in the order given, the
// total at most Cap. Returns the request id.
func Apply(cur realm, title, body, milestones string) int {
	if !cur.IsCurrent() {
		panic("govgrant: spoofed realm")
	}
	applicant := cur.Previous().Address()
	return file(applicant, applicant, "", title, body, milestones)
}

// ApplyFor files a grant request whose tranches pay beneficiary rather than
// the caller, with a reason for the detour. An empty account cannot pay the
// gas to ask for its first coins, so this is how most first grants arrive.
func ApplyFor(cur realm, beneficiary, reason, title, body, milestones string) int {
	if !cur.IsCurrent() {
		panic("govgrant: spoofed realm")
	}
	applicant := cur.Previous().Address()
	return file(applicant, address(beneficiary), reason, title, body, milestones)
}

func file(applicant, beneficiary address, reason, title, body, milestones string) int {
	r, err := program.ApplyFor(applicant, beneficiary, reason, title, body, milestones,
		runtime.ChainHeight())
	if err != nil {
		panic(err)
	}
	chain.Emit("Apply", "id", strconv.Itoa(r.ID), "applicant", applicant.String(),
		"beneficiary", r.Payee().String(), "total", strconv.FormatInt(r.Total(), 10))
	return r.ID
}

// ProposeMember asks the board to add or remove a member. Members only. A
// board of two cannot remove a member by itself; that takes GovDAO.
func ProposeMember(cur realm, addr string, add bool, body string) int {
	if !cur.IsCurrent() {
		panic("govgrant: spoofed realm")
	}
	proposer := cur.Previous().Address()
	r, err := program.Board.SubmitMemberChange(proposer, address(addr), add, body, runtime.ChainHeight())
	if err != nil {
		panic(err)
	}
	chain.Emit("ProposeMember", "id", strconv.Itoa(r.ID), "subject", addr,
		"add", strconv.FormatBool(add))
	return r.ID
}

// Retract pulls the caller's own request before it is decided.
func Retract(cur realm, id int) {
	if !cur.IsCurrent() {
		panic("govgrant: spoofed realm")
	}
	caller := cur.Previous().Address()
	if err := program.Board.Withdraw(caller, id, runtime.ChainHeight()); err != nil {
		panic(err)
	}
	chain.Emit("Retract", "id", strconv.Itoa(id))
}

// Vote records a member's ballot, with the reason rendered next to it.
func Vote(cur realm, id int, approve bool, reason string) {
	if !cur.IsCurrent() {
		panic("govgrant: spoofed realm")
	}
	voter := cur.Previous().Address()
	st, err := program.Board.Vote(voter, id, approve, reason, runtime.ChainHeight())
	if err != nil {
		panic(err)
	}
	chain.Emit("Vote", "id", strconv.Itoa(id), "voter", voter.String(),
		"approve", strconv.FormatBool(approve), "status", st.String())
}

// SubmitProof offers evidence for the next milestone of an approved grant.
// kind is "url", "hash" or "text"; ref is the link, digest or statement.
func SubmitProof(cur realm, id, milestone int, kind, ref, note string) {
	if !cur.IsCurrent() {
		panic("govgrant: spoofed realm")
	}
	caller := cur.Previous().Address()
	p := grants.Proof{Kind: kind, Ref: ref, Note: note, Height: runtime.ChainHeight()}
	if err := program.Board.SubmitProof(caller, id, milestone, p); err != nil {
		panic(err)
	}
	chain.Emit("SubmitProof", "id", strconv.Itoa(id),
		"milestone", strconv.Itoa(milestone), "kind", kind)
}

// Review records a member's verdict on the proof under review. The verdict
// that carries also pays the tranche, in this same transaction. A verdict the
// treasury cannot cover, or one cast while payouts are paused, is refused
// outright and changes nothing.
func Review(cur realm, id, milestone int, accept bool, reason string) {
	if !cur.IsCurrent() {
		panic("govgrant: spoofed realm")
	}
	voter := cur.Previous().Address()
	out, pay, err := program.Review(voter, id, milestone, accept, reason, runtime.ChainHeight(), Balance())
	if err != nil {
		panic(err)
	}
	chain.Emit("Review", "id", strconv.Itoa(id), "milestone", strconv.Itoa(milestone),
		"voter", voter.String(), "accept", strconv.FormatBool(accept), "outcome", out.String())
	if pay == nil {
		return
	}
	banker.NewBanker(banker.BankerTypeRealmSend, cur).
		SendCoins(Address(), pay.To, chain.NewCoins(chain.NewCoin(Denom, pay.Amount)))
	chain.Emit("Release", "id", strconv.Itoa(id), "milestone", strconv.Itoa(milestone),
		"to", pay.To.String(), "amount", strconv.FormatInt(pay.Amount, 10))
}
