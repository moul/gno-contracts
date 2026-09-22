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
type Program struct {
	Board     *Board
	Denom     string
	Donations []Donation
	Payments  []Payment
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
	return p.Board.SubmitFor(applicant, beneficiary, reason, title, body, ms, height)
}

// Review casts a member's verdict on the proof under review and, when that
// verdict releases the tranche, records the payment and hands it back for the
// caller to execute.
//
// balance is what the treasury holds right now. A verdict that would release
// more than that is refused with ErrUnderfunded and changes NOTHING: no
// ballot, no release, no payment. That ordering is the reason Board.Review is
// not called directly by a realm. A refusal is always free to record, since it
// costs the treasury nothing.
func (p *Program) Review(voter address, id, idx int, accept bool, reason string, height, balance int64) (Outcome, *Payment, error) {
	if releases, out := p.Board.ReviewDecides(id, idx, voter, accept); releases && out == Accepted {
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
