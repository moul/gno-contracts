package grants

import (
	"strconv"
	"strings"
)

// Program is a Board plus the money that moves around it: what came in, what
// went out, and the denomination it is all counted in.
//
// It still holds no coins and calls no banker. A realm hands it the current
// treasury balance whenever a decision depends on one, and executes the
// Payment it hands back. That split is the whole point: everything a grant
// program decides is testable without a node, and the realm on top is thin
// enough to read in one screen.
//
// Cap, Paused and Sweep are for a FUNDED board, one whose money comes from
// someone standing above the members (a DAO) rather than from the members
// themselves. They are the funder's levers, and a realm exposes them to the
// funder only: the members can neither raise the cap nor unpause themselves.
type Program struct {
	Board     *Board
	Denom     string
	Donations []Donation
	Payments  []Payment
	Sweeps    []Sweep

	// Cap is the most one grant request may ask for in total, or 0 for no
	// cap. It is checked when a request is filed, so lowering it does not
	// touch grants already approved: the board's promises stand.
	Cap int64

	// Paused refuses every verdict that would release a tranche. Filing,
	// voting and refusing proofs still work, so the record keeps moving while
	// the money stops.
	Paused bool
}

// Donation is one top-up of the treasury, credited to a name.
type Donation struct {
	Height int64
	From   address
	Amount int64
}

// Payment is one released tranche. The ledger of these is a program's answer
// to "where did the money go".
type Payment struct {
	Height    int64
	Request   int
	Milestone int
	To        address
	Amount    int64
}

// Sweep is money taken out of the treasury by the funder, not paid as a
// grant: unspent budget handed back, or a board wound down.
type Sweep struct {
	Height int64
	To     address
	Amount int64
}

// NewProgram returns a program whose board is seated with founders. denom is
// the coin everything is counted in ("ugnot" on gno.land); it is carried so a
// renderer can label amounts without the realm telling it twice.
func NewProgram(denom string, founders ...address) *Program {
	return &Program{Board: New(founders...), Denom: denom}
}

// Fund records a top-up. The coins have already moved by the time this is
// called: a realm calls it to put a name next to a transfer that would
// otherwise be anonymous.
func (p *Program) Fund(from address, amount, height int64) error {
	if amount <= 0 {
		return ErrNothingSent
	}
	if !from.IsValid() {
		return ErrBadAddress
	}
	p.Donations = append(p.Donations, Donation{Height: height, From: from, Amount: amount})
	return nil
}

// Apply files a grant request from a milestone spec, "design:100,ship:400".
// See ParseMilestones for the grammar.
func (p *Program) Apply(applicant address, title, body, spec string, height int64) (*Request, error) {
	return p.ApplyFor(applicant, applicant, "", title, body, spec, height)
}

// ApplyFor is Apply for a request whose money goes to someone other than the
// address filing it. See Board.SubmitFor for why the reason is required.
func (p *Program) ApplyFor(applicant, beneficiary address, reason, title, body, spec string, height int64) (*Request, error) {
	ms, err := ParseMilestones(spec)
	if err != nil {
		return nil, err
	}
	if p.Cap > 0 {
		var total int64
		for _, m := range ms {
			// Each amount is checked against the cap before it is added, so
			// the sum can never wrap around int64 and sneak under it.
			if m.Amount > p.Cap || total > p.Cap-m.Amount {
				return nil, ErrOverCap
			}
			total += m.Amount
		}
	}
	return p.Board.SubmitFor(applicant, beneficiary, reason, title, body, ms, height)
}

// SetCap sets the most one request may ask for; 0 removes the cap.
func (p *Program) SetCap(cap int64) error {
	if cap < 0 {
		return ErrBadCap
	}
	p.Cap = cap
	return nil
}

// Sweep records money the funder takes back out of the treasury and hands it
// back for the caller to execute, as Review does for a tranche. balance is
// what the treasury holds right now; a sweep larger than that is refused.
//
// It is deliberately not limited to the unpromised part of the balance: the
// funder may need to empty a board that has gone wrong, and a grantee's
// recourse then is the funder, not the contract. A renderer should show the
// promised amount next to the sweeps so that choice is visible.
func (p *Program) Sweep(to address, amount, height, balance int64) (*Sweep, error) {
	if amount <= 0 {
		return nil, ErrNothingSent
	}
	if !to.IsValid() {
		return nil, ErrBadAddress
	}
	if amount > balance {
		return nil, ErrUnderfunded
	}
	s := Sweep{Height: height, To: to, Amount: amount}
	p.Sweeps = append(p.Sweeps, s)
	return &s, nil
}

// Swept is everything ever taken back out through Sweep.
func (p *Program) Swept() int64 {
	var n int64
	for _, s := range p.Sweeps {
		n += s.Amount
	}
	return n
}

// Review casts a member's verdict on the proof under review and, when that
// verdict releases the tranche, records the payment and hands it back for the
// caller to execute.
//
// balance is what the treasury holds right now. A verdict that would release
// more than that is refused with ErrUnderfunded, and one that would release
// anything while the program is Paused with ErrPaused; either changes
// NOTHING: no ballot, no release, no payment. That ordering is the reason Board.Review is
// not called directly by a realm. A refusal is always free to record, since it
// costs the treasury nothing.
func (p *Program) Review(voter address, id, idx int, accept bool, reason string, height, balance int64) (Outcome, *Payment, error) {
	if releases, out := p.Board.ReviewDecides(id, idx, voter, accept); releases && out == Accepted {
		if p.Paused {
			return UnderReview, nil, ErrPaused
		}
		if amount := p.Board.Get(id).Milestones[idx].Amount; balance < amount {
			return UnderReview, nil, ErrUnderfunded
		}
	}

	out, err := p.Board.Review(voter, id, idx, accept, reason, height)
	if err != nil || out != Accepted {
		return out, nil, err
	}

	r := p.Board.Get(id)
	pay := Payment{
		Height:    height,
		Request:   id,
		Milestone: idx,
		To:        r.Payee(),
		Amount:    r.Milestones[idx].Amount,
	}
	p.Payments = append(p.Payments, pay)
	return out, &pay, nil
}

// Raised is everything ever donated through Fund.
func (p *Program) Raised() int64 {
	var n int64
	for _, d := range p.Donations {
		n += d.Amount
	}
	return n
}

// Disbursed is everything ever released.
func (p *Program) Disbursed() int64 { return p.Board.Disbursed() }

// Committed is what approved grants can still claim.
func (p *Program) Committed() int64 { return p.Board.Committed() }

// Available is balance minus what is already promised. It goes NEGATIVE when
// the board has approved more than the treasury holds, which is allowed on
// purpose: a board that can only approve what it already has cannot approve
// anything before a donor shows up. Renderers say so out loud.
func (p *Program) Available(balance int64) int64 { return balance - p.Committed() }

// ParseMilestones reads "design:100,ship:400" into milestones, amounts in the
// program's denomination, paid in the order written. A title may not contain a
// comma, and the amount is whatever follows the LAST colon, so
// "port gno:land tooling:250" parses the way it reads.
func ParseMilestones(spec string) ([]*Milestone, error) {
	out := []*Milestone{}
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
		out = append(out, NewMilestone(strings.TrimSpace(part[:i]), amount))
	}
	if len(out) == 0 {
		return nil, ErrBadSpec
	}
	return out, nil
}
