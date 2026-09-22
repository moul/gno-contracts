package forge

import "gno.land/p/nt/avl/v0"

// Change states.
const (
	StateOpen   = "open"
	StateMerged = "merged"
	StateClosed = "closed"
)

// Review verdicts.
const (
	VerdictApprove        = "approve"
	VerdictRequestChanges = "request-changes"
	VerdictComment        = "comment"
)

// Change is a change request (a pull request): a claim that TargetRef should be
// moved to include HeadOID, plus the reviews of that claim.
//
// Reviews are bound to the object id they reviewed, not to the change. Push a
// new head and every earlier approval stops counting: not by a policy toggle a
// maintainer can switch off, but because the approval names an object that is
// no longer what is being merged.
type Change struct {
	ID         int64
	Title      string
	Body       string
	Author     address
	SourceRepo string // forge repo id, or a mirror locator; "" means this repo
	SourceRef  string
	HeadOID    string
	TargetRef  string
	State      string
	CreatedAt  int64
	UpdatedAt  int64

	MergedOID string // the object TargetRef moved to
	MergedBy  address
	MergedAt  int64

	reviews     *avl.Tree // address string -> *Review (latest per reviewer)
	comments    *avl.Tree // padded id -> *Comment
	nextComment int64
}

// Review is one reviewer's verdict on one object id.
type Review struct {
	Reviewer address
	Verdict  string
	OID      string // the head the reviewer actually looked at
	Body     string
	Height   int64
}

// OpenChange files a change request. Permissionless, like an issue: the
// proposal costs its author gas and deposit, and costs a maintainer nothing
// until they choose to look.
func (r *Repo) OpenChange(actor address, height int64, title, body, sourceRepo, sourceRef, headOID, targetRef string) (*Change, error) {
	if r.Archived {
		return nil, ErrRepoArchived
	}
	if title == "" || !ValidLine(title, MaxTitleLen) {
		return nil, ErrInvalidText
	}
	if !ValidText(body, MaxBodyLen) {
		return nil, ErrInvalidText
	}
	if sourceRepo != "" && !ValidRepoID(sourceRepo) && !ValidMirror(sourceRepo) {
		return nil, ErrInvalidRepoID
	}
	if sourceRef != "" && !ValidRefName(sourceRef) {
		return nil, ErrInvalidRefName
	}
	if !ValidOID(headOID) {
		return nil, ErrInvalidOID
	}
	if !ValidRefName(targetRef) {
		return nil, ErrInvalidRefName
	}
	c := &Change{
		ID:         r.nextChange,
		Title:      title,
		Body:       body,
		Author:     actor,
		SourceRepo: sourceRepo,
		SourceRef:  sourceRef,
		HeadOID:    headOID,
		TargetRef:  targetRef,
		State:      StateOpen,
		CreatedAt:  height,
		UpdatedAt:  height,
		reviews:    avl.NewTree(),
		comments:   avl.NewTree(),
	}
	r.changes.Set(seqKey(c.ID), c)
	r.nextChange++
	return c, nil
}

// UpdateChangeHead repoints an open change at a new object. The author may
// always update their own; a writer may update anyone's (the "maintainer pushed
// a fixup" case).
func (r *Repo) UpdateChangeHead(actor address, height, id int64, headOID string) error {
	c := r.Change(id)
	if c == nil {
		return ErrChangeNotFound
	}
	if c.State != StateOpen {
		return ErrChangeNotOpen
	}
	if c.Author != actor && !r.Can(actor, RoleWriter) {
		return ErrUnauthorized
	}
	if !ValidOID(headOID) {
		return ErrInvalidOID
	}
	if headOID == c.HeadOID {
		return ErrSameOID
	}
	c.HeadOID = headOID
	c.UpdatedAt = height
	return nil
}

// ReviewChange records a verdict against the change's current head. Anyone may
// review; only a writer's approval counts toward the merge policy (see
// CountApprovals): an unprivileged review is signal, not authority.
func (r *Repo) ReviewChange(actor address, height, id int64, verdict, body string) error {
	if r.Archived {
		return ErrRepoArchived
	}
	c := r.Change(id)
	if c == nil {
		return ErrChangeNotFound
	}
	if c.State != StateOpen {
		return ErrChangeNotOpen
	}
	switch verdict {
	case VerdictApprove, VerdictRequestChanges, VerdictComment:
	default:
		return ErrInvalidVerdict
	}
	if verdict == VerdictApprove && actor == c.Author && !r.AllowSelfApproval {
		return ErrSelfApproval
	}
	if !ValidText(body, MaxCommentLen) {
		return ErrInvalidText
	}
	c.reviews.Set(actor.String(), &Review{
		Reviewer: actor,
		Verdict:  verdict,
		OID:      c.HeadOID,
		Body:     body,
		Height:   height,
	})
	c.UpdatedAt = height
	return nil
}

// CommentChange appends a reply to a change request.
func (r *Repo) CommentChange(actor address, height, id int64, body string) (*Comment, error) {
	if r.Archived {
		return nil, ErrRepoArchived
	}
	c := r.Change(id)
	if c == nil {
		return nil, ErrChangeNotFound
	}
	if body == "" || !ValidText(body, MaxCommentLen) {
		return nil, ErrInvalidText
	}
	cm := &Comment{ID: c.nextComment, Author: actor, Body: body, CreatedAt: height}
	c.comments.Set(seqKey(cm.ID), cm)
	c.nextComment++
	c.UpdatedAt = height
	return cm, nil
}

// CloseChange withdraws or rejects a change. Author or maintainer.
func (r *Repo) CloseChange(actor address, height, id int64) error {
	c := r.Change(id)
	if c == nil {
		return ErrChangeNotFound
	}
	if c.State != StateOpen {
		return ErrChangeNotOpen
	}
	if c.Author != actor && !r.Can(actor, RoleMaintainer) {
		return ErrUnauthorized
	}
	c.State = StateClosed
	c.UpdatedAt = height
	return nil
}

// CountApprovals counts approvals that still apply: cast by a writer or above,
// against the change's current head, and (unless the repo allows it) not the
// author's own.
func (r *Repo) CountApprovals(c *Change) int {
	n := 0
	c.reviews.Iterate("", "", func(_ string, value any) bool {
		rv := value.(*Review)
		if rv.Verdict != VerdictApprove || rv.OID != c.HeadOID {
			return false
		}
		if rv.Reviewer == c.Author && !r.AllowSelfApproval {
			return false
		}
		if !r.Can(rv.Reviewer, RoleWriter) {
			return false
		}
		n++
		return false
	})
	return n
}

// CountBlocking counts writers who requested changes on the current head.
func (r *Repo) CountBlocking(c *Change) int {
	n := 0
	c.reviews.Iterate("", "", func(_ string, value any) bool {
		rv := value.(*Review)
		if rv.Verdict == VerdictRequestChanges && rv.OID == c.HeadOID && r.Can(rv.Reviewer, RoleWriter) {
			n++
		}
		return false
	})
	return n
}

// MergeChange moves TargetRef to mergedOID and records the move as one more
// entry in the reference log, tagged with the change it came from.
//
// expectedTargetOID is a compare-and-swap on the target ref ("" when the ref
// does not exist yet): a change approved against one base cannot be merged onto
// a base that moved underneath it. mergedOID is computed off chain by whoever
// performs the merge: the chain records the claim, signed, ordered and
// attributed, and a client with the objects verifies that the result actually
// contains HeadOID.
func (r *Repo) MergeChange(actor address, height, id int64, expectedTargetOID, mergedOID, note string) (*LogEntry, error) {
	if r.Archived {
		return nil, ErrRepoArchived
	}
	c := r.Change(id)
	if c == nil {
		return nil, ErrChangeNotFound
	}
	if c.State != StateOpen {
		return nil, ErrChangeNotOpen
	}
	if !r.Can(actor, RoleMaintainer) {
		return nil, ErrUnauthorized
	}
	if !ValidOID(mergedOID) {
		return nil, ErrInvalidOID
	}
	if !ValidLine(note, MaxNoteLen) {
		return nil, ErrInvalidText
	}
	if r.CountBlocking(c) > 0 {
		return nil, ErrChangesRequested
	}
	if r.CountApprovals(c) < r.RequiredApprovals {
		return nil, ErrNotEnoughApproval
	}
	cur := r.Ref(c.TargetRef)
	switch {
	case cur == nil && expectedTargetOID != "":
		return nil, ErrRefNotFound
	case cur != nil && cur.OID != expectedTargetOID:
		return nil, ErrStaleRef
	case cur != nil && cur.OID == mergedOID:
		return nil, ErrSameOID
	}
	old := ""
	if cur != nil {
		old = cur.OID
	}
	r.refs.Set(c.TargetRef, &Ref{Name: c.TargetRef, OID: mergedOID, UpdatedAt: height, UpdatedBy: actor})
	e := r.appendLog(actor, height, c.TargetRef, old, mergedOID, KindMerge, c.ID, note)
	c.State = StateMerged
	c.MergedOID = mergedOID
	c.MergedBy = actor
	c.MergedAt = height
	c.UpdatedAt = height
	return e, nil
}

// Change returns a change by id, or nil.
func (r *Repo) Change(id int64) *Change {
	v := r.changes.Get(seqKey(id))
	if v == nil {
		return nil
	}
	return v.(*Change)
}

// IterateChanges walks change requests newest-first.
func (r *Repo) IterateChanges(offset, count int, cb func(*Change) bool) {
	if count <= 0 {
		count = r.changes.Size()
	}
	r.changes.ReverseIterateByOffset(offset, count, func(_ string, value any) bool {
		return cb(value.(*Change))
	})
}

// OpenChangeCount counts change requests still open.
func (r *Repo) OpenChangeCount() int {
	n := 0
	r.changes.Iterate("", "", func(_ string, value any) bool {
		if value.(*Change).State == StateOpen {
			n++
		}
		return false
	})
	return n
}

// ReviewCount is the number of reviewers who have weighed in (latest verdict
// per reviewer, on any head).
func (c *Change) ReviewCount() int { return c.reviews.Size() }

// Review returns a reviewer's latest verdict, or nil.
func (c *Change) Review(a address) *Review {
	v := c.reviews.Get(a.String())
	if v == nil {
		return nil
	}
	return v.(*Review)
}

// IterateReviews walks reviews in reviewer-address order.
func (c *Change) IterateReviews(cb func(*Review) bool) {
	c.reviews.Iterate("", "", func(_ string, value any) bool {
		return cb(value.(*Review))
	})
}

// CommentCount is the number of replies on the change.
func (c *Change) CommentCount() int { return c.comments.Size() }

// IterateComments walks replies oldest-first.
func (c *Change) IterateComments(offset, count int, cb func(*Comment) bool) {
	if count <= 0 {
		count = c.comments.Size()
	}
	c.comments.IterateByOffset(offset, count, func(_ string, value any) bool {
		return cb(value.(*Comment))
	})
}

// Stale reports whether a review no longer applies to the change's head.
func (c *Change) Stale(rv *Review) bool { return rv.OID != c.HeadOID }
