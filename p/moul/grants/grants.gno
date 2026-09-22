// Package grants is a grant board governed by a member set: anyone may ask
// the board for money, the members vote in the open, and the money leaves in
// tranches that each have to be earned by producing a proof the members
// accept.
//
// The package is pure. It holds no coins, reads no chain state and imports
// nothing from `chain`: the caller supplies the acting address and the block
// height, and the caller performs the transfer. That is what makes the whole
// state machine unit-testable without a node, and it is what lets the same
// board be driven by a realm, by a test, or by a different payment rail.
// Live board: gno.land/r/moul/grant/v0.
//
// # The shape of a grant
//
// A Request is a title, a body, and an ordered list of Milestones, each with
// its own amount. Approving a request does not pay anything: it only makes the
// first milestone claimable. To get a tranche the applicant submits a Proof
// (a URL, a hash, or plain text) and the members review that specific proof.
// A rejected proof does not kill the grant, it just closes one Attempt; the
// applicant submits another. Every attempt, accepted or not, stays on the
// record with the ballots that decided it.
//
// # Asking for someone else
//
// A request has an applicant, who files it and answers for it, and a
// beneficiary, who gets paid. SubmitFor separates the two and takes a reason
// for the detour; Submit is the common case where they are the same address.
//
// The split is not a convenience. An account with nothing in it cannot pay the
// gas to ask for its first coins, so on a board whose whole purpose is to fund
// empty accounts, "someone else files it" is the ONLY path that works. Both
// addresses are then barred from voting on the request, and either of them may
// submit a proof, for the same reason: the payee may not be able to transact
// at all until the first tranche lands.
//
// # Who may vote
//
// Every member, once, per decision. The party the decision is about is
// excluded: the applicant does not vote on their own grant, and the subject of
// a membership change does not vote on their own membership. The bar is a
// majority of the addresses that are actually eligible, recomputed on each
// ballot, so a board that grows mid-vote raises its own bar.
//
// # What this deliberately does not do
//
// No weights, no delegation, no quadratic anything, no deadline. A request
// with no majority either way simply stays Pending until someone breaks the
// tie or the applicant withdraws it. Those are all reasonable things to add on
// top; none of them is needed to show the shape.
package grants

import (
	"errors"
	"strconv"

	"gno.land/p/nt/avl/v0"
)

// Errors returned by the mutators. They are sentinels so a realm can map them
// onto its own messages, or simply panic with them.
var (
	ErrNotMember     = errors.New("grants: not a board member")
	ErrNotApplicant  = errors.New("grants: only the applicant may do this")
	ErrNoRequest     = errors.New("grants: no such request")
	ErrNoMilestone   = errors.New("grants: no such milestone")
	ErrNotPending    = errors.New("grants: the request is not pending")
	ErrNotApproved   = errors.New("grants: the request is not approved")
	ErrAlreadyVoted  = errors.New("grants: this member already voted")
	ErrConflict      = errors.New("grants: the party a decision is about may not vote on it")
	ErrOutOfOrder    = errors.New("grants: milestones are claimed in order")
	ErrProofPending  = errors.New("grants: a proof is already under review")
	ErrNoProof       = errors.New("grants: no proof is under review")
	ErrBadTitle      = errors.New("grants: title must be 1 to 100 characters")
	ErrBadBody       = errors.New("grants: body must be at most 2000 characters")
	ErrBadMilestones = errors.New("grants: a grant needs 1 to 10 milestones")
	ErrBadAmount     = errors.New("grants: every milestone must ask for a positive amount")
	ErrBadProof      = errors.New("grants: proof kind must be url, hash or text, with a reference")
	ErrBadReason     = errors.New("grants: reason must be at most 300 characters")
	ErrNeedReason    = errors.New("grants: filing for someone else needs a reason")
	ErrBadAddress    = errors.New("grants: invalid address")
	ErrIsMember      = errors.New("grants: already a board member")
	ErrLastMember    = errors.New("grants: the last member cannot be removed")
	ErrNothingSent   = errors.New("grants: a donation must be a positive amount")
	ErrUnderfunded   = errors.New("grants: the treasury cannot cover this tranche")
	ErrBadSpec       = errors.New("grants: milestones must read \"title:amount,title:amount\"")
)

// Limits every input is checked against. Exported so a UI can pre-validate.
const (
	MaxTitle      = 100
	MaxBody       = 2000
	MaxReason     = 300
	MaxRef        = 300
	MaxNote       = 500
	MaxMilestones = 10
)

// Status is where a request sits in its lifecycle.
type Status int

const (
	Pending   Status = iota // open for member ballots
	Approved                // carried; milestones can be earned
	Rejected                // a majority voted no
	Completed               // every milestone released
	Withdrawn               // the applicant pulled it before a decision
)

func (s Status) String() string {
	switch s {
	case Pending:
		return "pending"
	case Approved:
		return "approved"
	case Rejected:
		return "rejected"
	case Completed:
		return "completed"
	case Withdrawn:
		return "withdrawn"
	}
	return "unknown"
}

// Kind says what carrying a request actually does.
type Kind int

const (
	KindGrant  Kind = iota // pays out, milestone by milestone
	KindMember             // adds or removes a board member, immediately
)

func (k Kind) String() string {
	if k == KindMember {
		return "membership"
	}
	return "grant"
}

// Outcome is the result of one proof attempt.
type Outcome int

const (
	UnderReview Outcome = iota // members are still voting on this proof
	Accepted                   // the tranche is earned
	Refused                    // this proof did not convince; another may
)

func (o Outcome) String() string {
	switch o {
	case Accepted:
		return "accepted"
	case Refused:
		return "refused"
	}
	return "under review"
}

// Ballot is one member's vote on one decision, with the reason they gave.
// Reasons are not optional decoration: they are the only part of a vote that
// tells an applicant what to fix.
type Ballot struct {
	Voter   address
	Approve bool
	Reason  string
	Height  int64
}

// Proof is the evidence an applicant offers for one milestone. Kind is "url",
// "hash" or "text"; the board decides what it is worth.
type Proof struct {
	Kind   string
	Ref    string
	Note   string
	Height int64
}

// Attempt is one proof and the review it got. A milestone keeps every attempt,
// so a refused proof and the reasons it was refused stay readable forever.
type Attempt struct {
	Proof    Proof
	Reviews  []Ballot
	Outcome  Outcome
	ClosedAt int64
}

// Milestone is one tranche of a grant: what has to be shown, and what it pays.
type Milestone struct {
	Title      string
	Amount     int64 // in the smallest unit of whatever the realm pays in
	Attempts   []*Attempt
	Released   bool
	ReleasedAt int64
}

// Current returns the attempt still under review, or nil.
func (m *Milestone) Current() *Attempt {
	if len(m.Attempts) == 0 {
		return nil
	}
	last := m.Attempts[len(m.Attempts)-1]
	if last.Outcome == UnderReview {
		return last
	}
	return nil
}

// Request is a grant application or a membership change.
type Request struct {
	ID          int
	Kind        Kind
	Applicant   address // who filed it and answers for it
	Beneficiary address // who gets paid; equal to Applicant on a self request
	Reason      string  // why the applicant is asking on someone else's behalf
	Title       string
	Body        string
	Milestones  []*Milestone
	Subject     address // KindMember only: the address being added or removed
	Add         bool    // KindMember only: true adds, false removes
	Votes       []Ballot
	Status      Status
	CreatedAt   int64
	DecidedAt   int64
}

// OnBehalf reports whether this grant was filed by one address for another.
func (r *Request) OnBehalf() bool {
	return r.Kind == KindGrant && r.Beneficiary != r.Applicant
}

// Payee is the address a released tranche pays. It is the beneficiary, which
// is the applicant unless the request was filed for someone else.
func (r *Request) Payee() address {
	if r.Beneficiary.IsValid() {
		return r.Beneficiary
	}
	return r.Applicant
}

// Total is the sum of every milestone, released or not.
func (r *Request) Total() int64 {
	var n int64
	for _, m := range r.Milestones {
		n += m.Amount
	}
	return n
}

// Paid is what the milestones released so far add up to.
func (r *Request) Paid() int64 {
	var n int64
	for _, m := range r.Milestones {
		if m.Released {
			n += m.Amount
		}
	}
	return n
}

// Outstanding is what an approved request can still cost the treasury. It is
// zero for anything not approved, which is what makes it safe to sum across
// the board as the committed amount.
func (r *Request) Outstanding() int64 {
	if r.Status != Approved {
		return 0
	}
	return r.Total() - r.Paid()
}

// Next is the index of the first unreleased milestone, or -1 when the grant is
// fully paid. Milestones are earned in order.
func (r *Request) Next() int {
	for i, m := range r.Milestones {
		if !m.Released {
			return i
		}
	}
	return -1
}

// Tally counts the ballots cast on the request itself.
func (r *Request) Tally() (yes, no int) {
	return count(r.Votes)
}

// BallotOf returns the member's ballot on the request, or nil.
func (r *Request) BallotOf(voter address) *Ballot {
	return find(r.Votes, voter)
}

// Excludes reports whether addr is barred from voting on this request because
// the decision is about them.
//
// A grant excludes BOTH parties, not just the one who typed the transaction:
// letting a member be paid by a request a friend filed for them is the same
// conflict with one more step in it.
func (r *Request) Excludes(addr address) bool {
	if r.Kind == KindMember {
		return addr == r.Subject
	}
	return addr == r.Applicant || addr == r.Payee()
}

func count(bs []Ballot) (yes, no int) {
	for _, b := range bs {
		if b.Approve {
			yes++
		} else {
			no++
		}
	}
	return yes, no
}

func find(bs []Ballot, voter address) *Ballot {
	for i := range bs {
		if bs[i].Voter == voter {
			return &bs[i]
		}
	}
	return nil
}

// Board is the whole state of one grant program: who decides, and what has
// been asked of them.
type Board struct {
	members  *avl.Tree // address string -> int64 join height
	requests *avl.Tree // zero-padded id -> *Request
	nextID   int
}

// New returns a board whose founding members are the given addresses, all
// recorded as having joined at height 0. Duplicates and invalid addresses are
// skipped; a board with no members accepts no decisions until one is added, so
// callers normally pass at least one.
func New(founders ...address) *Board {
	b := &Board{members: avl.NewTree(), requests: avl.NewTree(), nextID: 1}
	for _, f := range founders {
		if f.IsValid() {
			b.members.Set(f.String(), int64(0))
		}
	}
	return b
}

// IsMember reports whether addr sits on the board.
func (b *Board) IsMember(addr address) bool { return b.members.Has(addr.String()) }

// MemberCount is the number of addresses on the board.
func (b *Board) MemberCount() int { return b.members.Size() }

// Members lists the board in address order, which is stable across calls.
func (b *Board) Members() []address {
	out := make([]address, 0, b.members.Size())
	b.members.Iterate("", "", func(k string, _ any) bool {
		out = append(out, address(k))
		return false
	})
	return out
}

// JoinedAt returns the height a member joined, or -1 for a non-member.
func (b *Board) JoinedAt(addr address) int64 {
	v := b.members.Get(addr.String())
	if v == nil {
		return -1
	}
	return v.(int64)
}

// Eligible is how many members may vote on a request: everyone but the parties
// the decision is about.
func (b *Board) Eligible(r *Request) int {
	n := 0
	b.members.Iterate("", "", func(k string, _ any) bool {
		if !r.Excludes(address(k)) {
			n++
		}
		return false
	})
	return n
}

// Majority is the number of concurring ballots a decision on r needs. It is
// recomputed on every ballot, so a board that changes size mid-vote moves its
// own bar rather than freezing a stale one.
func (b *Board) Majority(r *Request) int {
	n := b.Eligible(r)
	if n <= 0 {
		return 1 // an unreachable bar beats a bar of zero
	}
	return n/2 + 1
}

// Get returns a request by id, or nil.
func (b *Board) Get(id int) *Request {
	v := b.requests.Get(idKey(id))
	if v == nil {
		return nil
	}
	return v.(*Request)
}

// Size is the number of requests ever filed.
func (b *Board) Size() int { return b.requests.Size() }

// List returns every request in id order.
func (b *Board) List() []*Request {
	out := make([]*Request, 0, b.requests.Size())
	b.requests.Iterate("", "", func(_ string, v any) bool {
		out = append(out, v.(*Request))
		return false
	})
	return out
}

// Committed is what the treasury still owes on approved grants. A realm that
// keeps its balance at or above this number can always pay a released tranche.
func (b *Board) Committed() int64 {
	var n int64
	b.requests.Iterate("", "", func(_ string, v any) bool {
		n += v.(*Request).Outstanding()
		return false
	})
	return n
}

// Disbursed is everything the board has ever released.
func (b *Board) Disbursed() int64 {
	var n int64
	b.requests.Iterate("", "", func(_ string, v any) bool {
		n += v.(*Request).Paid()
		return false
	})
	return n
}

// idKey pads an id so avl iteration is numeric, not lexicographic: unpadded
// keys sort "1","10","2" and every listing would lose its order past nine
// entries. ufmt has no width flags in gno, so the padding is by hand.
func idKey(id int) string {
	s := strconv.Itoa(id)
	for len(s) < 8 {
		s = "0" + s
	}
	return s
}
