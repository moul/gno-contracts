// Package grantsdao is a working grant program: a treasury anyone can top up,
// a board of members who decide in public, and applicants who get paid one
// milestone at a time, each one against a proof the board accepted.
//
// The state machine lives in gno.land/p/moul/x/grants/v0, which is pure and
// knows nothing about coins. This realm is the half that touches the chain:
// it owns the singleton board, turns the caller into an address and the block
// into a height, moves ugnot through the banker, and renders the whole thing.
//
// # The flow
//
//	Fund          anyone sends ugnot to the treasury, and is named for it
//	Apply         anyone asks for money, split into milestones
//	Vote          members carry or kill the application, with a reason
//	SubmitProof   the applicant shows what they did for the next milestone
//	Review        members accept or refuse that proof, with a reason
//	              -> accepting it pays the tranche, in the same transaction
//
// # What "transparent" means here, concretely
//
// Nothing about a decision is private or derived. Every ballot is stored with
// its voter, its reason and the height it was cast at, and Render prints all
// of them, including the ones on proofs that were refused. Every payment is
// appended to a ledger with the height, the request, the milestone, the payee
// and the amount, and every payment also emits an event. The treasury panel
// prints the balance next to what the board has already promised, so an
// over-committed board is visible on the front page rather than discovered at
// payout time.
//
// # The treasury is not escrowed
//
// Approving a grant promises money; it does not move or lock any. Committed()
// is what approved-but-unreleased milestones add up to, Available() is the
// balance minus that, and Available() can go negative when the board approves
// more than it holds. That is deliberate: a board that can only approve what
// it already has cannot approve anything before a donor shows up. The cost is
// that a release can fail for lack of funds, so Review refuses the verdict
// that would release a tranche the treasury cannot pay, and changes nothing.
//
// # Who the caller is
//
// Every actor is PreviousRealm().Address(), the immediate caller. Called
// through another realm that is the calling REALM, not the user behind it.
// A realm can therefore be a member, an applicant or a donor, which is a
// feature (a DAO can hold a seat) and worth knowing before you wire one up.
package grantsdao

import (
	"errors"
	"strconv"
	"strings"

	"chain"
	"chain/banker"
	"chain/runtime"
	"chain/runtime/unsafe"

	"gno.land/p/moul/x/grants/v0"
)

// Denom is the only coin this board holds or pays.
const Denom = "ugnot"

// Path is this realm's package path, used for its treasury address and for
// the links Render emits.
const Path = "gno.land/r/moul/x/grantsdao/v0"

// Founders seats the board at deploy. Hardcoded rather than taken from the
// deployer: inside a plain `func Test(t *testing.T)` the gno test runner
// reports OriginCaller() as the EMPTY address, so a board seeded from it is
// empty in every test and something else on chain. That divergence is exactly
// where an authorization bug hides, so the addresses are written down.
var Founders = []address{
	"g1manfred47kzduec920z88wfr64ylksmdcedlf5",
	"g1us8428u2a5satrlxzagqqa5m6vmuze025anjlj",
	"g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5",
}

var (
	ErrNothingSent = errors.New("grantsdao: send some ugnot along with the call")
	ErrUnderfunded = errors.New("grantsdao: the treasury cannot cover this tranche")
	ErrBadSpec     = errors.New("grantsdao: milestones must read \"title:amount,title:amount\", amounts in ugnot")
)

// Donation is one top-up of the treasury.
type Donation struct {
	Height int64
	From   address
	Amount int64
}

// Payment is one released tranche. The ledger of these is the realm's answer
// to "where did the money go".
type Payment struct {
	Height    int64
	Request   int
	Milestone int
	To        address
	Amount    int64
}

var (
	board     *grants.Board
	donations []Donation
	payments  []Payment
)

func init() { seed() }

// Address is the treasury: the realm's own package address. Fund it by
// sending ugnot to it, or by calling Fund with `-send`.
func Address() address { return chain.PackageAddress(Path) }

// Balance is what the treasury actually holds.
func Balance() int64 {
	return banker.NewReadonlyBanker().GetCoins(Address()).AmountOf(Denom)
}

// Committed is what approved grants can still claim.
func Committed() int64 { return board.Committed() }

// Available is the balance minus what is already promised. It goes negative
// when the board has approved more than it holds, which Render says out loud.
func Available() int64 { return Balance() - Committed() }

// Disbursed is everything ever paid out.
func Disbursed() int64 { return board.Disbursed() }

// Raised is everything ever donated through Fund.
func Raised() int64 {
	var n int64
	for _, d := range donations {
		n += d.Amount
	}
	return n
}

// Members lists the board.
func Members() []address { return board.Members() }

// Fund credits the ugnot sent with the call to the treasury and puts the
// donor on the record. Coins sent to the realm address directly still land in
// the treasury; they just do not get a name next to them.
func Fund(cur realm) {
	amount := unsafe.OriginSend().AmountOf(Denom)
	if amount <= 0 {
		panic(ErrNothingSent)
	}
	from := unsafe.PreviousRealm().Address()
	donations = append(donations, Donation{Height: runtime.ChainHeight(), From: from, Amount: amount})
	chain.Emit("Fund", "from", from.String(), "amount", strconv.FormatInt(amount, 10))
}

// Apply files a grant request. milestones reads "title:amount,title:amount",
// amounts in ugnot, paid in the order given. Returns the request id.
func Apply(cur realm, title, body, milestones string) int {
	ms, err := parseMilestones(milestones)
	if err != nil {
		panic(err)
	}
	applicant := unsafe.PreviousRealm().Address()
	r, err := board.Submit(applicant, title, body, ms, runtime.ChainHeight())
	if err != nil {
		panic(err)
	}
	chain.Emit("Apply",
		"id", strconv.Itoa(r.ID),
		"applicant", applicant.String(),
		"total", strconv.FormatInt(r.Total(), 10))
	return r.ID
}

// ProposeMember asks the board to add or remove a member. Members only.
func ProposeMember(cur realm, addr string, add bool, body string) int {
	proposer := unsafe.PreviousRealm().Address()
	r, err := board.SubmitMemberChange(proposer, address(addr), add, body, runtime.ChainHeight())
	if err != nil {
		panic(err)
	}
	chain.Emit("ProposeMember",
		"id", strconv.Itoa(r.ID),
		"subject", addr,
		"add", strconv.FormatBool(add))
	return r.ID
}

// Retract pulls the caller's own request before it is decided.
func Retract(cur realm, id int) {
	caller := unsafe.PreviousRealm().Address()
	if err := board.Withdraw(caller, id, runtime.ChainHeight()); err != nil {
		panic(err)
	}
	chain.Emit("Retract", "id", strconv.Itoa(id))
}

// Vote records a member's ballot on a request. The reason is stored and
// rendered next to the vote: it is the only part of a decision that tells an
// applicant what to do about it.
func Vote(cur realm, id int, approve bool, reason string) {
	voter := unsafe.PreviousRealm().Address()
	st, err := board.Vote(voter, id, approve, reason, runtime.ChainHeight())
	if err != nil {
		panic(err)
	}
	chain.Emit("Vote",
		"id", strconv.Itoa(id),
		"voter", voter.String(),
		"approve", strconv.FormatBool(approve),
		"status", st.String())
}

// SubmitProof offers evidence for the next milestone of an approved grant.
// kind is "url", "hash" or "text"; ref is the link, digest or statement.
func SubmitProof(cur realm, id, milestone int, kind, ref, note string) {
	caller := unsafe.PreviousRealm().Address()
	p := grants.Proof{Kind: kind, Ref: ref, Note: note, Height: runtime.ChainHeight()}
	if err := board.SubmitProof(caller, id, milestone, p); err != nil {
		panic(err)
	}
	chain.Emit("SubmitProof",
		"id", strconv.Itoa(id),
		"milestone", strconv.Itoa(milestone),
		"kind", kind)
}

// Review records a member's verdict on the proof under review. The verdict
// that carries the accept majority also pays the tranche, in this same
// transaction, which is why an underfunded treasury makes Review refuse the
// verdict outright instead of marking a milestone released that nobody can
// pay.
func Review(cur realm, id, milestone int, accept bool, reason string) {
	voter := unsafe.PreviousRealm().Address()

	// Check before recording: the board is the source of truth for whether
	// the tranche is earned, but the treasury is the source of truth for
	// whether it can be handed over.
	if releases, out := board.ReviewDecides(id, milestone, voter, accept); releases && out == grants.Accepted {
		if amount := board.Get(id).Milestones[milestone].Amount; Balance() < amount {
			panic(ErrUnderfunded)
		}
	}

	out, err := board.Review(voter, id, milestone, accept, reason, runtime.ChainHeight())
	if err != nil {
		panic(err)
	}
	chain.Emit("Review",
		"id", strconv.Itoa(id),
		"milestone", strconv.Itoa(milestone),
		"voter", voter.String(),
		"accept", strconv.FormatBool(accept),
		"outcome", out.String())

	if out == grants.Accepted {
		pay(cur, board.Get(id), milestone)
	}
}

// pay moves one released tranche out of the treasury and onto the ledger.
func pay(cur realm, r *grants.Request, idx int) {
	m := r.Milestones[idx]
	bnk := banker.NewBanker(banker.BankerTypeRealmSend, cur)
	bnk.SendCoins(Address(), r.Applicant, chain.NewCoins(chain.NewCoin(Denom, m.Amount)))

	payments = append(payments, Payment{
		Height:    runtime.ChainHeight(),
		Request:   r.ID,
		Milestone: idx,
		To:        r.Applicant,
		Amount:    m.Amount,
	})
	chain.Emit("Release",
		"id", strconv.Itoa(r.ID),
		"milestone", strconv.Itoa(idx),
		"to", r.Applicant.String(),
		"amount", strconv.FormatInt(m.Amount, 10),
		"status", r.Status.String())
}

// parseMilestones turns "design:100,ship:400" into milestones. A title may
// not contain a comma, and the amount is whatever follows the LAST colon, so
// "port gno:land tooling:250" parses the way it reads.
func parseMilestones(spec string) ([]*grants.Milestone, error) {
	out := []*grants.Milestone{}
	for _, part := range strings.Split(spec, ",") {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		i := strings.LastIndex(part, ":")
		if i < 0 {
			return nil, ErrBadSpec
		}
		amount, err := strconv.ParseInt(strings.TrimSpace(part[i+1:]), 10, 64)
		if err != nil {
			return nil, ErrBadSpec
		}
		out = append(out, grants.NewMilestone(strings.TrimSpace(part[:i]), amount))
	}
	if len(out) == 0 {
		return nil, ErrBadSpec
	}
	return out, nil
}
