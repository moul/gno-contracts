package forge

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

func TestSetRefCompareAndSwap(t *testing.T) {
	_, r := newRepo(t)

	// Create: the expectation is "this ref does not exist".
	e, err := r.SetRef(carol, 101, "refs/heads/main", "", oid("a"), "initial import")
	urequire.NoError(t, err)
	uassert.Equal(t, KindCreate, e.Kind)
	uassert.Equal(t, int64(0), e.Seq)
	uassert.Equal(t, "", e.OldOID)
	uassert.Equal(t, oid("a"), r.Ref("refs/heads/main").OID)
	uassert.Equal(t, carol.String(), r.Ref("refs/heads/main").UpdatedBy.String())

	// Creating twice is a mistake, not an overwrite.
	_, err = r.SetRef(carol, 102, "refs/heads/main", "", oid("b"), "")
	uassert.ErrorIs(t, err, ErrRefExists)

	// A stale expectation is exactly the lost-push case --force-with-lease
	// exists to catch, and here the lease is held by consensus.
	_, err = r.SetRef(carol, 102, "refs/heads/main", oid("9"), oid("b"), "")
	uassert.ErrorIs(t, err, ErrStaleRef)

	// A fresh expectation succeeds and chains onto the previous entry.
	e2, err := r.SetRef(carol, 103, "refs/heads/main", oid("a"), oid("b"), "fix the thing")
	urequire.NoError(t, err)
	uassert.Equal(t, KindUpdate, e2.Kind)
	uassert.Equal(t, oid("a"), e2.OldOID)
	uassert.Equal(t, EntryDigest(e.Digest, e2), e2.Digest, "digest commits to its predecessor")
	uassert.Equal(t, e2.Digest, r.LogHead())

	// No-op writes are rejected: they would cost a deposit and record nothing.
	_, err = r.SetRef(carol, 104, "refs/heads/main", oid("b"), oid("b"), "")
	uassert.ErrorIs(t, err, ErrSameOID)

	// Updating a ref that does not exist is not a create.
	_, err = r.SetRef(carol, 104, "refs/heads/other", oid("a"), oid("b"), "")
	uassert.ErrorIs(t, err, ErrRefNotFound)
}

func TestSetRefAuthorizationAndValidation(t *testing.T) {
	_, r := newRepo(t)

	_, err := r.SetRef(eve, 101, "refs/heads/main", "", oid("a"), "")
	uassert.ErrorIs(t, err, ErrUnauthorized, "a stranger cannot move a ref")
	_, err = r.SetRef(dave, 101, "refs/heads/main", "", oid("a"), "")
	uassert.ErrorIs(t, err, ErrUnauthorized, "a reader cannot move a ref")

	_, err = r.SetRef(carol, 101, "main", "", oid("a"), "")
	uassert.ErrorIs(t, err, ErrInvalidRefName)
	_, err = r.SetRef(carol, 101, "refs/heads/main", "", "deadbeef", "")
	uassert.ErrorIs(t, err, ErrInvalidOID)
	_, err = r.SetRef(carol, 101, "refs/heads/main", "", oid("a"), "two\nlines")
	uassert.ErrorIs(t, err, ErrInvalidText, "a note is one line: it is a digest field")
}

func TestForceAndDelete(t *testing.T) {
	_, r := newRepo(t)
	_, err := r.SetRef(carol, 101, "refs/heads/main", "", oid("a"), "initial")
	urequire.NoError(t, err)
	_, err = r.SetRef(carol, 102, "refs/heads/wip", "", oid("c"), "wip")
	urequire.NoError(t, err)

	// A writer cannot force. A maintainer can, and it is on the record forever.
	_, err = r.ForceSetRef(carol, 103, "refs/heads/main", oid("d"), "rewrite")
	uassert.ErrorIs(t, err, ErrUnauthorized)
	e, err := r.ForceSetRef(bob, 103, "refs/heads/main", oid("d"), "drop the bad commit")
	urequire.NoError(t, err)
	uassert.Equal(t, KindForce, e.Kind)
	uassert.Equal(t, oid("a"), e.OldOID, "the abandoned tip stays in the log")

	// Delete is compare-and-swap too, and the default branch is not deletable.
	_, err = r.DeleteRef(bob, 104, "refs/heads/main", oid("d"), "")
	uassert.ErrorIs(t, err, ErrUnauthorized)
	_, err = r.DeleteRef(bob, 104, "refs/heads/wip", oid("9"), "")
	uassert.ErrorIs(t, err, ErrStaleRef)
	_, err = r.DeleteRef(carol, 104, "refs/heads/wip", oid("c"), "")
	uassert.ErrorIs(t, err, ErrUnauthorized)
	de, err := r.DeleteRef(bob, 104, "refs/heads/wip", oid("c"), "merged")
	urequire.NoError(t, err)
	uassert.Equal(t, KindDelete, de.Kind)
	uassert.Equal(t, "", de.NewOID)
	uassert.Equal(t, 1, r.RefCount(), "the ref is gone")
	uassert.Equal(t, 4, r.LogSize(), "the history of it is not")

	_, err = r.DeleteRef(bob, 105, "refs/heads/wip", "", "")
	uassert.ErrorIs(t, err, ErrRefNotFound)
}

func TestLogChainVerifies(t *testing.T) {
	_, r := newRepo(t)
	urequire.Equal(t, "", r.LogHead())

	for i, o := range []string{"a", "b", "c", "d"} {
		expected := ""
		if i > 0 {
			expected = r.Ref("refs/heads/main").OID
		}
		_, err := r.SetRef(carol, int64(100+i), "refs/heads/main", expected, oid(o), "step")
		urequire.NoError(t, err)
	}
	uassert.Equal(t, 4, r.LogSize())

	ok, bad := r.VerifyLog()
	uassert.True(t, ok, "an untouched log verifies")
	uassert.Equal(t, int64(-1), bad)

	// Rewrite history the only way it can be rewritten here: reaching into the
	// package's own memory, and the chain detects it at the doctored entry.
	r.LogEntryAt(1).NewOID = oid("f")
	ok, bad = r.VerifyLog()
	uassert.False(t, ok, "a doctored entry breaks the chain")
	uassert.Equal(t, int64(1), bad)
}

func TestLogIteration(t *testing.T) {
	_, r := newRepo(t)
	for i, o := range []string{"a", "b", "c"} {
		expected := ""
		if i > 0 {
			expected = r.Ref("refs/heads/main").OID
		}
		_, err := r.SetRef(carol, int64(100+i), "refs/heads/main", expected, oid(o), "")
		urequire.NoError(t, err)
	}

	var fwd []string
	r.IterateLog(0, 0, func(e *LogEntry) bool {
		fwd = append(fwd, e.NewOID[:1])
		return false
	})
	uassert.Equal(t, "a,b,c", join(fwd))

	var rev []string
	r.IterateLogReverse(0, 2, func(e *LogEntry) bool {
		rev = append(rev, e.NewOID[:1])
		return false
	})
	uassert.Equal(t, "c,b", join(rev), "newest-first, paginated")

	var names []string
	r.IterateRefs(func(ref *Ref) bool {
		names = append(names, ref.Name)
		return false
	})
	uassert.Equal(t, "refs/heads/main", join(names))
	uassert.True(t, r.LogEntryAt(99) == nil)
}
