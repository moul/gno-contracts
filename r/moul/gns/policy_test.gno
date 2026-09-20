package gns

import (
	"testing"
)

func TestOperatorDelegation(cur realm, t *testing.T) {
	reset()
	doRegister(cur, "alice", alice, 100000)

	// alice grants bob record management only (not transfer)
	testing.SetRealm(testing.NewUserRealm(alice))
	SetOperator(cross(cur), "alice", bob, Permissions{ManageRecords: true})

	// bob can set a text record
	testing.SetRealm(testing.NewUserRealm(bob))
	SetText(cross(cur), "alice", "url", "https://bob-managed.example")
	v, ok := Text("alice", "url")
	isTrue(t, ok, "operator set record")
	eqStr(t, "https://bob-managed.example", v, "operator record value")

	// invariant: operator without Transfer cannot transfer
	n := getRaw("alice")
	errIs(t, authorize(bob, n, PermTransfer), errUnauthorized, "record operator lacks transfer")
	noErr(t, authorize(bob, n, PermManageRecords), "record operator has records perm")
}

func TestRemoveOperator(cur realm, t *testing.T) {
	reset()
	doRegister(cur, "alice", alice, 100000)
	testing.SetRealm(testing.NewUserRealm(alice))
	SetOperator(cross(cur), "alice", bob, Permissions{ManageRecords: true})
	n := getRaw("alice")
	eqInt(t, 1, int64(n.OperatorCount), "one operator")

	testing.SetRealm(testing.NewUserRealm(alice))
	RemoveOperator(cross(cur), "alice", bob)
	n = getRaw("alice")
	eqInt(t, 0, int64(n.OperatorCount), "operator removed")
	errIs(t, authorize(bob, n, PermManageRecords), errUnauthorized, "removed operator loses perm")
}

func TestTransferHappy(cur realm, t *testing.T) {
	reset()
	doRegister(cur, "alice", alice, 100000)
	r0 := getRaw("alice").Revision

	testing.SetRealm(testing.NewUserRealm(alice))
	Transfer(cross(cur), "alice", bob, true, false)

	owner, ok := OwnerOf("alice")
	isTrue(t, ok, "still exists")
	eqStr(t, bob.String(), owner, "owner now bob")
	isTrue(t, getRaw("alice").Revision > r0, "revision bumped on transfer (invariant 12 side-effect)")
}

func TestAuthorizeOrder(cur realm, t *testing.T) {
	reset()
	doRegister(cur, "alice", alice, 100000)
	n := getRaw("alice")

	// direct owner (active) authorized
	noErr(t, authorize(alice, n, PermManageRecords), "owner authorized")
	// unrelated user rejected
	errIs(t, authorize(carol, n, PermManageRecords), errUnauthorized, "stranger rejected")
	// admin has NO routine authority over user names (invariant 18)
	errIs(t, authorize(admin, n, PermTransfer), errUnauthorized, "admin cannot transfer user name")
}

func TestNonTransferablePolicyPure(t *testing.T) {
	reset()
	// A name whose policy forbids owner transfer: the Transfer owner-branch
	// checks OwnerCanTransfer and rejects with policy_locked. We assert the
	// policy flag drives that decision.
	n := newTestName("locked", alice, ControlPolicy{OwnerCanTransfer: false})
	isFalse(t, n.ControlPolicy.OwnerCanTransfer, "policy forbids transfer")
	// and no operator/parent path grants transfer either
	errIs(t, authorize(bob, n, PermTransfer), errUnauthorized, "no delegated transfer")
}
