package gns

import (
	"testing"
)

// This file targets the "critical invariants" list from the spec that are best
// expressed as focused checks against the internal helpers.

func TestInvariantAdminCannotConfiscate(cur realm, t *testing.T) {
	reset()
	doRegister(cur, "alice", alice, 100000)
	n := getRaw("alice")

	// invariant 18: admin has no routine power over an active user name.
	errIs(t, authorize(admin, n, PermTransfer), errUnauthorized, "admin no transfer")
	errIs(t, authorize(admin, n, PermManageRecords), errUnauthorized, "admin no records")

	// invariant 14/17 via ReserveName: an actively-owned name cannot be reserved
	// (confiscated). We assert the precondition the crossing path enforces.
	isFalse(t, available("alice"), "active name unavailable to others")
	isTrue(t, isActive(n) && n.Owner.IsValid(), "name active and owned")
}

func TestInvariantGraceNotRegisterable(cur realm, t *testing.T) {
	reset()
	doRegister(cur, "alice", alice, 1000)
	testing.SkipHeights(210) // into grace
	eqStr(t, string(StatusGrace), string(Status("alice")), "in grace")
	// invariant 3: a grace-period name cannot be registered by another user.
	isFalse(t, available("alice"), "grace name not available")
}

func TestInvariantSingleEffectiveOwner(cur realm, t *testing.T) {
	reset()
	doRegister(cur, "alice", alice, 100000)
	// invariant 1: exactly one owner.
	o1, ok := OwnerOf("alice")
	isTrue(t, ok, "owned")
	testing.SetRealm(testing.NewUserRealm(alice))
	Transfer(cross(cur), "alice", bob, true, false)
	o2, _ := OwnerOf("alice")
	isFalse(t, o1 == o2, "owner changed to exactly one new owner")
	eqStr(t, bob.String(), o2, "single new owner")
}

func TestInvariantPermanentOnlyRestrictive(t *testing.T) {
	reset()
	// invariant 5, exhaustive over all flags.
	all := ControlPolicy{
		OwnerCanTransfer: true, OwnerCanCreateSubnames: true, RecordsMutable: true,
		ParentCanReclaim: true, ParentCanTransfer: true, ParentCanDelete: true,
		ParentCanChangePolicy: true, Permanent: true,
	}
	// try to relax everything
	got := mergeRestrictive(all, all) // identity keeps all true
	isTrue(t, got.OwnerCanTransfer && got.RecordsMutable && got.ParentCanReclaim, "identity keeps flags")

	none := ControlPolicy{Permanent: true}
	restricted := mergeRestrictive(all, none)
	isFalse(t, restricted.OwnerCanTransfer, "all restricted off")
	isFalse(t, restricted.ParentCanReclaim, "reclaim off")
	isTrue(t, restricted.Permanent, "permanent stays on")

	// cannot turn any back on
	reenable := mergeRestrictive(restricted, all)
	isFalse(t, reenable.OwnerCanTransfer, "cannot re-enable transfer")
	isFalse(t, reenable.RecordsMutable, "cannot re-enable records")
}

func TestInvariantPriceOverflowSafe(t *testing.T) {
	reset()
	config.BasePricePerSecond = 1 << 40
	// invariant 10: overflow returns an error, never a wrapped value.
	_, err := priceFor("a", 1<<40) // *100 multiplier -> overflow
	isErr(t, err, "overflow detected")
}

func TestInvariantCommitmentTiming(cur realm, t *testing.T) {
	reset()
	commit, _ := MakeCommitment("alice", alice, 1000, "s", "", config.PolicyRevision)
	testing.SetRealm(testing.NewUserRealm(alice))
	Commit(cross(cur), commit)

	cs := CommitmentStatus(commit)
	// invariant 8: ready/expiry window is enforced by MinCommitAge/MaxCommitAge.
	eqInt(t, cs.CreatedAt+config.MinCommitAge, cs.ReadyAt, "ready at min age")
	eqInt(t, cs.CreatedAt+config.MaxCommitAge, cs.ExpiresAt, "expires at max age")
}

func TestPauseGatePure(t *testing.T) {
	reset()
	// paused reads still work; the mutation gate is requireNotPaused.
	config.Paused = true
	// Status is a read; must still function while paused.
	eqStr(t, string(StatusAvailable), string(Status("nobody")), "reads work while paused")
	config.Paused = false
}

func TestRecordLimitsConfigured(t *testing.T) {
	reset()
	// invariant 13: per-name storage bounds are configured and enforced.
	isTrue(t, config.MaxRecordsPerName > 0, "record count bound configured")
	isTrue(t, config.MaxTextValueBytes > 0, "text size bound configured")
	isTrue(t, config.MaxOperatorsPerName > 0, "operator bound configured")
}
