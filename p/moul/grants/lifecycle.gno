package grants

// This file holds every state transition of the board. Each one takes the
// acting address and the block height from the caller rather than reading
// them from the chain, which is what keeps the package pure and the whole
// lifecycle exercisable in a plain unit test.

// NewMilestone is a small constructor so callers do not build the struct (and
// its Attempts slice) by hand.
func NewMilestone(title string, amount int64) *Milestone {
	return &Milestone{Title: title, Amount: amount}
}

// Submit files a grant application for the applicant themselves. Anyone may
// apply; being a member is not required and does not help, since a member is
// barred from voting on their own request.
func (b *Board) Submit(applicant address, title, body string, ms []*Milestone, height int64) (*Request, error) {
	return b.SubmitFor(applicant, applicant, "", title, body, ms, height)
}

// SubmitFor files a grant application whose money goes to beneficiary rather
// than to the applicant, with a reason for the detour.
//
// The reason is required, and it is required because it is the only thing on
// the page that answers the question a reader will have: why is this person
// asking for someone else's money. The usual honest answer is that the payee
// has an empty account and cannot pay the gas to ask, which is exactly the
// case a grant board exists to serve and exactly the case an impersonation
// looks like. Making the claim explicit is what lets a member check it.
//
// Passing the applicant's own address is the same as Submit and needs no
// reason.
func (b *Board) SubmitFor(applicant, beneficiary address, reason, title, body string, ms []*Milestone, height int64) (*Request, error) {
	if !applicant.IsValid() || !beneficiary.IsValid() {
		return nil, ErrBadAddress
	}
	if len(reason) > MaxReason {
		return nil, ErrBadReason
	}
	if beneficiary != applicant && reason == "" {
		return nil, ErrNeedReason
	}
	if err := checkTitle(title); err != nil {
		return nil, err
	}
	if len(body) > MaxBody {
		return nil, ErrBadBody
	}
	if len(ms) == 0 || len(ms) > MaxMilestones {
		return nil, ErrBadMilestones
	}
	for _, m := range ms {
		if m == nil || m.Amount <= 0 {
			return nil, ErrBadAmount
		}
		if err := checkTitle(m.Title); err != nil {
			return nil, err
		}
	}
	return b.file(&Request{
		Kind:        KindGrant,
		Applicant:   applicant,
		Beneficiary: beneficiary,
		Reason:      reason,
		Title:       title,
		Body:        body,
		Milestones:  ms,
		CreatedAt:   height,
	}), nil
}

// SubmitMemberChange files a request to add or remove a board member. Only a
// member may file one: opening the board's own composition to anyone with a
// keypair is how a grant board gets captured.
func (b *Board) SubmitMemberChange(proposer, subject address, add bool, body string, height int64) (*Request, error) {
	if !b.IsMember(proposer) {
		return nil, ErrNotMember
	}
	if !subject.IsValid() {
		return nil, ErrBadAddress
	}
	if len(body) > MaxBody {
		return nil, ErrBadBody
	}
	switch {
	case add && b.IsMember(subject):
		return nil, ErrIsMember
	case !add && !b.IsMember(subject):
		return nil, ErrNotMember
	case !add && b.MemberCount() == 1:
		return nil, ErrLastMember
	}
	title := "Remove " + subject.String()
	if add {
		title = "Add " + subject.String()
	}
	return b.file(&Request{
		Kind:        KindMember,
		Applicant:   proposer,
		Beneficiary: proposer,
		Title:       title,
		Body:        body,
		Subject:     subject,
		Add:         add,
		CreatedAt:   height,
	}), nil
}

func (b *Board) file(r *Request) *Request {
	r.ID = b.nextID
	b.nextID++
	b.requests.Set(idKey(r.ID), r)
	return r
}

// Withdraw lets an applicant pull their own request before it is decided.
func (b *Board) Withdraw(caller address, id int, height int64) error {
	r := b.Get(id)
	if r == nil {
		return ErrNoRequest
	}
	if r.Applicant != caller {
		return ErrNotApplicant
	}
	if r.Status != Pending {
		return ErrNotPending
	}
	r.Status, r.DecidedAt = Withdrawn, height
	return nil
}

// Standing counts only the ballots of addresses that are members right now.
// Decisions use this, not Request.Tally: a ballot is a permanent record of
// what someone said, but it stops carrying weight the moment they leave the
// board. The two numbers differ exactly when a voter has since been removed,
// and a good renderer shows both.
func (b *Board) Standing(r *Request) (yes, no int) { return b.standing(r.Votes) }

// Decides previews what a ballot would do without casting it, so a caller can
// check a precondition it cannot roll back: a realm, for instance, refusing
// to let a grant carry that its treasury cannot cover. It reports false for a
// ballot that would be refused anyway.
func (b *Board) Decides(id int, voter address, approve bool) (bool, Status) {
	r := b.Get(id)
	if r == nil || r.Status != Pending {
		return false, Pending
	}
	if !b.IsMember(voter) || r.Excludes(voter) || r.BallotOf(voter) != nil {
		return false, Pending
	}
	yes, no := b.Standing(r)
	if approve {
		yes++
	} else {
		no++
	}
	switch m := b.Majority(r); {
	case yes >= m:
		return true, Approved
	case no >= m:
		return true, Rejected
	}
	return false, Pending
}

// ReviewDecides is Decides for a proof review: it reports whether this
// verdict would close the attempt under review, and how. A realm uses it to
// check, before recording anything, that it can actually pay a tranche it is
// about to release.
func (b *Board) ReviewDecides(id, idx int, voter address, accept bool) (bool, Outcome) {
	r := b.Get(id)
	if r == nil || r.Kind != KindGrant || r.Status != Approved {
		return false, UnderReview
	}
	if idx < 0 || idx >= len(r.Milestones) {
		return false, UnderReview
	}
	a := r.Milestones[idx].Current()
	if a == nil {
		return false, UnderReview
	}
	if !b.IsMember(voter) || r.Excludes(voter) || find(a.Reviews, voter) != nil {
		return false, UnderReview
	}
	yes, no := b.standing(a.Reviews)
	if accept {
		yes++
	} else {
		no++
	}
	switch m := b.Majority(r); {
	case yes >= m:
		return true, Accepted
	case no >= m:
		return true, Refused
	}
	return false, UnderReview
}

// standing counts ballots from current members only. See Standing.
func (b *Board) standing(bs []Ballot) (yes, no int) {
	for _, v := range bs {
		if !b.IsMember(v.Voter) {
			continue
		}
		if v.Approve {
			yes++
		} else {
			no++
		}
	}
	return yes, no
}

// Vote casts one member's ballot on a request and returns the status it left
// the request in. A member votes once; there is no changing your mind, which
// is the price of every ballot being a permanent public statement.
func (b *Board) Vote(voter address, id int, approve bool, reason string, height int64) (Status, error) {
	r := b.Get(id)
	if r == nil {
		return Pending, ErrNoRequest
	}
	if !b.IsMember(voter) {
		return r.Status, ErrNotMember
	}
	if r.Status != Pending {
		return r.Status, ErrNotPending
	}
	if r.Excludes(voter) {
		return r.Status, ErrConflict
	}
	if r.BallotOf(voter) != nil {
		return r.Status, ErrAlreadyVoted
	}
	if len(reason) > MaxReason {
		return r.Status, ErrBadReason
	}

	r.Votes = append(r.Votes, Ballot{Voter: voter, Approve: approve, Reason: reason, Height: height})

	yes, no := b.Standing(r)
	switch m := b.Majority(r); {
	case yes >= m:
		r.Status, r.DecidedAt = Approved, height
		if r.Kind == KindMember {
			b.applyMemberChange(r, height)
		}
	case no >= m:
		r.Status, r.DecidedAt = Rejected, height
	}
	return r.Status, nil
}

// applyMemberChange is the whole execution engine for KindMember: a carried
// membership request takes effect at once, with nothing to claim afterwards,
// so it goes straight from Approved to Completed.
func (b *Board) applyMemberChange(r *Request, height int64) {
	if r.Add {
		b.members.Set(r.Subject.String(), height)
	} else {
		b.members.Remove(r.Subject.String())
	}
	r.Status = Completed
}

// SubmitProof offers evidence for the next unreleased milestone of an
// approved grant. Milestones are earned in order, and only one proof is under
// review at a time.
//
// Either the applicant or the beneficiary may submit. On a request filed for
// an empty account, the payee cannot transact until the first tranche lands,
// so restricting this to the payee would strand the grant it was filed to
// unstick; restricting it to the filer would leave the payee unable to show
// their own work once they can.
func (b *Board) SubmitProof(caller address, id, idx int, p Proof) error {
	r := b.Get(id)
	if r == nil {
		return ErrNoRequest
	}
	if r.Kind != KindGrant || r.Status != Approved {
		return ErrNotApproved
	}
	if r.Applicant != caller && r.Payee() != caller {
		return ErrNotApplicant
	}
	if idx < 0 || idx >= len(r.Milestones) {
		return ErrNoMilestone
	}
	if idx != r.Next() {
		return ErrOutOfOrder
	}
	if err := checkProof(p); err != nil {
		return err
	}
	m := r.Milestones[idx]
	if m.Current() != nil {
		return ErrProofPending
	}
	m.Attempts = append(m.Attempts, &Attempt{Proof: p, Outcome: UnderReview})
	return nil
}

// Review casts a member's verdict on the proof currently under review and
// returns the outcome that verdict left the attempt in. Accepting it releases
// the tranche, which in this package means marking it Released and nothing
// more; moving the coins is the caller's job, and Request.Paid tells it how
// much it now owes. Refusing closes the attempt and lets the applicant try
// again with better evidence.
func (b *Board) Review(voter address, id, idx int, accept bool, reason string, height int64) (Outcome, error) {
	r := b.Get(id)
	if r == nil {
		return UnderReview, ErrNoRequest
	}
	if !b.IsMember(voter) {
		return UnderReview, ErrNotMember
	}
	if r.Kind != KindGrant || r.Status != Approved {
		return UnderReview, ErrNotApproved
	}
	if idx < 0 || idx >= len(r.Milestones) {
		return UnderReview, ErrNoMilestone
	}
	if r.Excludes(voter) {
		return UnderReview, ErrConflict
	}
	if len(reason) > MaxReason {
		return UnderReview, ErrBadReason
	}
	m := r.Milestones[idx]
	a := m.Current()
	if a == nil {
		return UnderReview, ErrNoProof
	}
	if find(a.Reviews, voter) != nil {
		return UnderReview, ErrAlreadyVoted
	}

	a.Reviews = append(a.Reviews, Ballot{Voter: voter, Approve: accept, Reason: reason, Height: height})

	yes, no := b.standing(a.Reviews)
	switch mj := b.Majority(r); {
	case yes >= mj:
		a.Outcome, a.ClosedAt = Accepted, height
		m.Released, m.ReleasedAt = true, height
		if r.Next() == -1 {
			r.Status = Completed
		}
	case no >= mj:
		a.Outcome, a.ClosedAt = Refused, height
	}
	return a.Outcome, nil
}

func checkTitle(s string) error {
	if len(s) == 0 || len(s) > MaxTitle {
		return ErrBadTitle
	}
	return nil
}

func checkProof(p Proof) error {
	switch p.Kind {
	case "url", "hash", "text":
	default:
		return ErrBadProof
	}
	if len(p.Ref) == 0 || len(p.Ref) > MaxRef || len(p.Note) > MaxNote {
		return ErrBadProof
	}
	return nil
}
