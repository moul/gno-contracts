package forge

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

// openChange sets up a repo with main at oid("a") and one open change proposing
// oid("b"), authored by carol (a writer).
func openChange(t *testing.T) (*Repo, *Change) {
	t.Helper()
	_, r := newRepo(t)
	_, err := r.SetRef(alice, 100, "refs/heads/main", "", oid("a"), "initial")
	urequire.NoError(t, err)
	c, err := r.OpenChange(carol, 101, "add the log", "closes #1", "", "refs/heads/feat", oid("b"), "refs/heads/main")
	urequire.NoError(t, err)
	return r, c
}

func TestOpenChangeValidation(t *testing.T) {
	_, r := newRepo(t)

	_, err := r.OpenChange(eve, 101, "", "", "", "", oid("b"), "refs/heads/main")
	uassert.ErrorIs(t, err, ErrInvalidText)
	_, err = r.OpenChange(eve, 101, "t", "", "", "", "beef", "refs/heads/main")
	uassert.ErrorIs(t, err, ErrInvalidOID)
	_, err = r.OpenChange(eve, 101, "t", "", "", "", oid("b"), "main")
	uassert.ErrorIs(t, err, ErrInvalidRefName)
	_, err = r.OpenChange(eve, 101, "t", "", "NOT/an/id", "", oid("b"), "refs/heads/main")
	uassert.ErrorIs(t, err, ErrInvalidRepoID)

	// A fork or a plain git remote are both legal sources: the objects live
	// off chain either way.
	c, err := r.OpenChange(eve, 101, "from a fork", "", "eve/forge", "refs/heads/feat", oid("b"), "refs/heads/main")
	urequire.NoError(t, err)
	uassert.Equal(t, StateOpen, c.State)
	c2, err := r.OpenChange(eve, 101, "from a remote", "", "https://example.com/x.git", "refs/heads/feat", oid("b"), "refs/heads/main")
	urequire.NoError(t, err)
	uassert.Equal(t, int64(1), c2.ID)
	uassert.Equal(t, 2, r.OpenChangeCount())
}

func TestApprovalsAreBoundToTheReviewedObject(t *testing.T) {
	r, c := openChange(t)

	urequire.NoError(t, r.ReviewChange(bob, 102, 0, VerdictApprove, "lgtm"))
	uassert.Equal(t, 1, r.CountApprovals(c))

	// Push a new head: the approval named an object that is no longer what
	// would be merged, so it stops counting. Nothing had to remember to
	// dismiss it.
	urequire.NoError(t, r.UpdateChangeHead(carol, 103, 0, oid("c")))
	uassert.Equal(t, 0, r.CountApprovals(c))
	uassert.True(t, c.Stale(c.Review(bob)))

	urequire.NoError(t, r.ReviewChange(bob, 104, 0, VerdictApprove, "still lgtm"))
	uassert.Equal(t, 1, r.CountApprovals(c))
	uassert.Equal(t, 1, c.ReviewCount(), "one verdict per reviewer, latest wins")
}

func TestApprovalWeight(t *testing.T) {
	r, c := openChange(t)

	// Anyone may review; only a writer's approval counts toward policy.
	urequire.NoError(t, r.ReviewChange(eve, 102, 0, VerdictApprove, "as a user: works"))
	urequire.NoError(t, r.ReviewChange(dave, 102, 0, VerdictApprove, "reader here"))
	uassert.Equal(t, 2, c.ReviewCount())
	uassert.Equal(t, 0, r.CountApprovals(c), "unprivileged review is signal, not authority")

	// The author cannot approve their own change, unless the repo says so.
	uassert.ErrorIs(t, r.ReviewChange(carol, 102, 0, VerdictApprove, "mine"), ErrSelfApproval)
	urequire.NoError(t, r.SetPolicy(alice, 1, true))
	urequire.NoError(t, r.ReviewChange(carol, 102, 0, VerdictApprove, "mine"))
	uassert.Equal(t, 1, r.CountApprovals(c))

	uassert.ErrorIs(t, r.ReviewChange(bob, 102, 0, "lgtm?", ""), ErrInvalidVerdict)
	uassert.ErrorIs(t, r.ReviewChange(bob, 102, 9, VerdictApprove, ""), ErrChangeNotFound)
}

func TestMergePolicy(t *testing.T) {
	r, c := openChange(t)

	// Default policy is one approval.
	_, err := r.MergeChange(bob, 105, 0, oid("a"), oid("e"), "merge #0")
	uassert.ErrorIs(t, err, ErrNotEnoughApproval)

	urequire.NoError(t, r.ReviewChange(bob, 106, 0, VerdictApprove, "lgtm"))

	// A writer cannot merge, however well reviewed.
	_, err = r.MergeChange(carol, 107, 0, oid("a"), oid("e"), "")
	uassert.ErrorIs(t, err, ErrUnauthorized)

	// A blocking review stops the merge while it stands.
	urequire.NoError(t, r.ReviewChange(alice, 107, 0, VerdictRequestChanges, "needs a test"))
	uassert.Equal(t, 1, r.CountBlocking(c))
	_, err = r.MergeChange(bob, 108, 0, oid("a"), oid("e"), "")
	uassert.ErrorIs(t, err, ErrChangesRequested)
	urequire.NoError(t, r.ReviewChange(alice, 109, 0, VerdictApprove, "test added"))

	// The base moved: the change was approved against a tree that no longer
	// exists, so the merge is refused rather than silently rebased.
	_, err = r.MergeChange(bob, 110, 0, oid("9"), oid("e"), "")
	uassert.ErrorIs(t, err, ErrStaleRef)

	e, err := r.MergeChange(bob, 111, 0, oid("a"), oid("e"), "merge change 0")
	urequire.NoError(t, err)
	uassert.Equal(t, KindMerge, e.Kind)
	uassert.Equal(t, int64(0), e.ChangeID, "the log entry names the change it came from")
	uassert.Equal(t, oid("a"), e.OldOID)
	uassert.Equal(t, oid("e"), r.Ref("refs/heads/main").OID, "the ref moved")
	uassert.Equal(t, StateMerged, c.State)
	uassert.Equal(t, bob.String(), c.MergedBy.String())
	uassert.Equal(t, int64(111), c.MergedAt)
	uassert.Equal(t, 0, r.OpenChangeCount())

	ok, _ := r.VerifyLog()
	uassert.True(t, ok)

	// A merged change is closed to everything.
	_, err = r.MergeChange(bob, 112, 0, oid("e"), oid("f"), "")
	uassert.ErrorIs(t, err, ErrChangeNotOpen)
	uassert.ErrorIs(t, r.UpdateChangeHead(carol, 112, 0, oid("d")), ErrChangeNotOpen)
	uassert.ErrorIs(t, r.ReviewChange(bob, 112, 0, VerdictApprove, ""), ErrChangeNotOpen)
	uassert.ErrorIs(t, r.CloseChange(carol, 112, 0), ErrChangeNotOpen)
}

func TestMergeCreatesMissingRef(t *testing.T) {
	_, r := newRepo(t)
	c, err := r.OpenChange(carol, 101, "first branch", "", "", "refs/heads/feat", oid("b"), "refs/heads/main")
	urequire.NoError(t, err)
	urequire.NoError(t, r.SetPolicy(alice, 0, false))

	_, err = r.MergeChange(bob, 102, 0, oid("a"), oid("b"), "")
	uassert.ErrorIs(t, err, ErrRefNotFound, "a target that does not exist takes no expectation")

	e, err := r.MergeChange(bob, 103, 0, "", oid("b"), "first merge")
	urequire.NoError(t, err)
	uassert.Equal(t, KindMerge, e.Kind)
	uassert.Equal(t, "", e.OldOID)
	uassert.Equal(t, oid("b"), r.Ref("refs/heads/main").OID)
	uassert.Equal(t, StateMerged, c.State)
}

func TestChangeCommentsAndClose(t *testing.T) {
	r, c := openChange(t)

	cm, err := r.CommentChange(eve, 102, 0, "does this cover the force case?")
	urequire.NoError(t, err)
	uassert.Equal(t, int64(0), cm.ID)
	uassert.Equal(t, 1, c.CommentCount())
	_, err = r.CommentChange(eve, 102, 0, "")
	uassert.ErrorIs(t, err, ErrInvalidText)

	uassert.ErrorIs(t, r.CloseChange(eve, 103, 0), ErrUnauthorized)
	urequire.NoError(t, r.CloseChange(carol, 103, 0), "the author may withdraw")
	uassert.Equal(t, StateClosed, c.State)

	uassert.True(t, r.Change(42) == nil)
	uassert.ErrorIs(t, r.UpdateChangeHead(carol, 104, 42, oid("d")), ErrChangeNotFound)
}

func TestChangeIterationIsNewestFirst(t *testing.T) {
	_, r := newRepo(t)
	for _, title := range []string{"one", "two", "three"} {
		_, err := r.OpenChange(carol, 101, title, "", "", "", oid("b"), "refs/heads/main")
		urequire.NoError(t, err)
	}

	var got []string
	r.IterateChanges(0, 0, func(c *Change) bool {
		got = append(got, c.Title)
		return false
	})
	uassert.Equal(t, "three,two,one", join(got))

	var reviewers []string
	c := r.Change(0)
	urequire.NoError(t, r.ReviewChange(bob, 102, 0, VerdictApprove, ""))
	urequire.NoError(t, r.ReviewChange(alice, 102, 0, VerdictComment, ""))
	c.IterateReviews(func(rv *Review) bool {
		reviewers = append(reviewers, rv.Verdict)
		return false
	})
	uassert.Equal(t, 2, len(reviewers))
}
