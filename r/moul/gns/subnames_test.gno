package gns

import (
	"testing"
)

// setPolicy is a small helper: parent owner sets a registration policy.
func setPolicy(cur realm, parent string, owner address, mode string) {
	testing.SetRealm(testing.NewUserRealm(owner))
	SetRegistrationPolicy(cross(cur), parent, RegistrationPolicy{Mode: mode})
}

func TestSubnameOpen(cur realm, t *testing.T) {
	reset()
	doRegister(cur, "company", alice, 100000)
	setPolicy(cur, "company", alice, ModeOpen)

	// anyone (bob) can claim an open subname
	testing.SetRealm(testing.NewUserRealm(bob))
	CreateSubname(cross(cur), "company", "bob", bob, SubnameOptions{Duration: 100000})

	owner, ok := OwnerOf("bob.company")
	isTrue(t, ok, "subname exists")
	eqStr(t, bob.String(), owner, "subname owner is bob")

	n := getRaw("bob.company")
	eqStr(t, "company", n.Parent, "parent set")
	eqInt(t, 2, int64(n.Depth), "depth 2")
}

func TestSubnameOwnerMode(cur realm, t *testing.T) {
	reset()
	doRegister(cur, "company", alice, 100000)
	setPolicy(cur, "company", alice, ModeOwner)

	// parent owner can create
	testing.SetRealm(testing.NewUserRealm(alice))
	CreateSubname(cross(cur), "company", "team", carol, SubnameOptions{Duration: 100000})
	owner, ok := OwnerOf("team.company")
	isTrue(t, ok, "owner-mode subname created by parent owner")
	eqStr(t, carol.String(), owner, "assigned owner carol")

	// authorization for a non-owner is rejected at the gate (pure check on the
	// parent's ManageSubnames permission).
	p := getRaw("company")
	errIs(t, authorize(bob, p, PermManageSubnames), errUnauthorized, "bob cannot manage company subnames")
}

func TestSubnameClosedByDefault(cur realm, t *testing.T) {
	reset()
	doRegister(cur, "company", alice, 100000)
	// default policy after registration is Closed
	p := getRaw("company")
	eqStr(t, ModeClosed, p.RegistrationPolicy.Mode, "default closed")
}

func TestParentGenerationInvalidatesChild(cur realm, t *testing.T) {
	reset()
	doRegister(cur, "company", alice, 1000)
	setPolicy(cur, "company", alice, ModeOpen)
	testing.SetRealm(testing.NewUserRealm(bob))
	CreateSubname(cross(cur), "company", "api", bob, SubnameOptions{Duration: 1000000})

	isTrue(t, Exists("api.company"), "child exists initially")

	// expire the parent and re-register it (new generation)
	testing.SkipHeights(500) // beyond parent grace
	doRegister(cur, "company", carol, 1000)

	// invariant 16 / recycling: the old child must NOT silently survive under
	// the recycled parent (ParentGeneration mismatch).
	eqStr(t, string(StatusExpired), string(Status("api.company")), "orphaned child invalid")
	isFalse(t, Exists("api.company"), "recycled-parent child not resurrected")
}

func TestEmancipationRestrictOnly(t *testing.T) {
	reset()
	// invariant 5: a permanent policy can only become more restrictive.
	base := ControlPolicy{
		OwnerCanTransfer:       true,
		OwnerCanCreateSubnames: true,
		RecordsMutable:         true,
		ParentCanReclaim:       true,
		ParentCanTransfer:      true,
	}
	// try to RELAX ParentCanReclaim false->... and turn things on
	req := ControlPolicy{
		OwnerCanTransfer:       true,
		OwnerCanCreateSubnames: true,
		RecordsMutable:         true,
		ParentCanReclaim:       false, // restrict (allowed)
		ParentCanTransfer:      true,
		Permanent:              true,
	}
	got := mergeRestrictive(base, req)
	isFalse(t, got.ParentCanReclaim, "reclaim restricted true->false")
	isTrue(t, got.OwnerCanTransfer, "transfer kept true")
	isTrue(t, got.Permanent, "permanent turned on")

	// now, once permanent, attempting to RE-ENABLE reclaim must not work
	relax := ControlPolicy{
		OwnerCanTransfer:       true,
		OwnerCanCreateSubnames: true,
		RecordsMutable:         true,
		ParentCanReclaim:       true, // attempt to relax false->true
		ParentCanTransfer:      true,
		Permanent:              true,
	}
	got2 := mergeRestrictive(got, relax)
	isFalse(t, got2.ParentCanReclaim, "cannot relax false->true (invariant 5)")
}

func TestLockPolicyEmancipatesChild(cur realm, t *testing.T) {
	reset()
	doRegister(cur, "company", alice, 100000)
	setPolicy(cur, "company", alice, ModeOpen)
	testing.SetRealm(testing.NewUserRealm(bob))
	CreateSubname(cross(cur), "company", "wallet", bob, SubnameOptions{
		Duration:      100000,
		ControlPolicy: ControlPolicy{OwnerCanTransfer: true, RecordsMutable: true, ParentCanTransfer: true},
	})

	// child owner locks out parent transfer power
	testing.SetRealm(testing.NewUserRealm(bob))
	LockPolicy(cross(cur), "wallet.company", ControlPolicy{
		OwnerCanTransfer: true,
		RecordsMutable:   true,
		ParentCanTransfer: false, // remove parent power
		Permanent:        true,
	})

	child := getRaw("wallet.company")
	isFalse(t, child.ControlPolicy.ParentCanTransfer, "parent transfer removed")
	isTrue(t, child.ControlPolicy.Permanent, "now permanent")

	// invariant 4: parent can no longer transfer the child
	errIs(t, authorize(alice, child, PermTransfer), errUnauthorized, "parent lost transfer power")
}

func TestDeleteSubname(cur realm, t *testing.T) {
	reset()
	doRegister(cur, "company", alice, 100000)
	setPolicy(cur, "company", alice, ModeOpen)
	testing.SetRealm(testing.NewUserRealm(bob))
	CreateSubname(cross(cur), "company", "temp", bob, SubnameOptions{Duration: 100000})
	isTrue(t, Exists("temp.company"), "subname created")

	testing.SetRealm(testing.NewUserRealm(bob))
	DeleteSubname(cross(cur), "temp.company")
	isFalse(t, Exists("temp.company"), "subname deleted")
}
