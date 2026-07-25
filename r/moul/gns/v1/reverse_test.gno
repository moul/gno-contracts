package gns

import (
	"testing"
)

func TestPrimaryNameForwardVerified(cur realm, t *testing.T) {
	reset()
	doRegister(cur, "alice", alice, 100000)

	// forward address must point to the caller before SetPrimaryName succeeds
	testing.SetRealm(testing.NewUserRealm(alice))
	SetAddress(cross(cur), "alice", alice.String())
	testing.SetRealm(testing.NewUserRealm(alice))
	SetPrimaryName(cross(cur), "alice")

	name, ok := PrimaryName(alice.String())
	isTrue(t, ok, "primary resolves")
	eqStr(t, "alice", name, "primary is alice")
}

func TestPrimaryNameForwardMismatch(cur realm, t *testing.T) {
	reset()
	doRegister(cur, "alice", alice, 100000)

	testing.SetRealm(testing.NewUserRealm(alice))
	SetAddress(cross(cur), "alice", alice.String())
	testing.SetRealm(testing.NewUserRealm(alice))
	SetPrimaryName(cross(cur), "alice")

	// change the forward address away from alice -> primary must stop resolving
	testing.SetRealm(testing.NewUserRealm(alice))
	SetAddress(cross(cur), "alice", bob.String())

	// invariant 6: primary returned only when forward resolution matches
	_, ok := PrimaryName(alice.String())
	isFalse(t, ok, "stale reverse not returned")
}

func TestPrimaryNameExpired(cur realm, t *testing.T) {
	reset()
	doRegister(cur, "alice", alice, 1000)
	testing.SetRealm(testing.NewUserRealm(alice))
	SetAddress(cross(cur), "alice", alice.String())
	testing.SetRealm(testing.NewUserRealm(alice))
	SetPrimaryName(cross(cur), "alice")

	testing.SkipHeights(500) // expire the name
	_, ok := PrimaryName(alice.String())
	isFalse(t, ok, "expired name yields no primary")
}

func TestClearPrimaryName(cur realm, t *testing.T) {
	reset()
	doRegister(cur, "alice", alice, 100000)
	testing.SetRealm(testing.NewUserRealm(alice))
	SetAddress(cross(cur), "alice", alice.String())
	testing.SetRealm(testing.NewUserRealm(alice))
	SetPrimaryName(cross(cur), "alice")

	_, ok := PrimaryName(alice.String())
	isTrue(t, ok, "primary set")

	testing.SetRealm(testing.NewUserRealm(alice))
	ClearPrimaryName(cross(cur))
	_, ok = PrimaryName(alice.String())
	isFalse(t, ok, "primary cleared")
}

func TestTransferInvalidatesReverse(cur realm, t *testing.T) {
	reset()
	doRegister(cur, "alice", alice, 100000)
	testing.SetRealm(testing.NewUserRealm(alice))
	SetAddress(cross(cur), "alice", alice.String())
	testing.SetRealm(testing.NewUserRealm(alice))
	SetPrimaryName(cross(cur), "alice")

	// transfer to bob, clearing records -> forward no longer points to alice
	testing.SetRealm(testing.NewUserRealm(alice))
	Transfer(cross(cur), "alice", bob, true, true)

	_, ok := PrimaryName(alice.String())
	isFalse(t, ok, "reverse invalidated after transfer+record clear")
}
