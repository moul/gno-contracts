package gns

import (
	"testing"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/testutils/v0"
)

// Deterministic, checksum-valid test addresses.
var (
	admin = testutils.TestAddress("admin")
	alice = testutils.TestAddress("alice")
	bob   = testutils.TestAddress("bob")
	carol = testutils.TestAddress("carol")
	dave  = testutils.TestAddress("dave")
)

// reset re-initializes all package state to a deterministic, test-friendly
// configuration. Durations are small so lifecycle tests can advance time with
// modest SkipHeights calls. Pricing is free by default (BasePricePerSecond=0)
// so most functional tests need not attach payment; payment tests override it.
func reset() {
	names = avl.NewTree()
	commitments = avl.NewTree()
	reverse = avl.NewTree()
	events = avl.NewTree()
	byOwner = avl.NewTree()
	byParent = avl.NewTree()
	nextEventID = 0

	config = Config{
		Admin:            admin,
		Treasury:         admin,
		RegistrationOpen: true,

		MinCommitAge: 10,
		MaxCommitAge: 1000,

		MinRegistrationDuration: 100,
		MaxRegistrationDuration: 10_000_000,

		GracePeriod: 100,

		BasePricePerSecond: 0,
		PremiumByLength:    map[uint8]int64{1: 100, 2: 25, 3: 5, 4: 2},

		PaymentDenom: "ugnot",

		MaxTextValueBytes:   4096,
		MaxBinaryValueBytes: 8192,
		MaxRecordsPerName:   128,
		MaxOperatorsPerName: 32,

		PolicyRevision: 1,
	}
}

// newTestName builds a standalone active *Name for unit-testing pure helpers
// (authorize, statusOf, ...) without going through the registration flow.
func newTestName(canonical string, owner address, cp ControlPolicy) *Name {
	label, parent := splitLabel(canonical)
	return &Name{
		Canonical:     canonical,
		Owner:         owner,
		ExpiresAt:     now() + 1_000_000,
		Parent:        parent,
		Label:         label,
		Depth:         depthOf(canonical),
		Generation:    1,
		Revision:      1,
		Records:       newRecords(),
		Operators:     avl.NewTree(),
		ControlPolicy: cp,
	}
}

// doRegister runs the full commit→reveal flow for a second-level name using the
// free (zero-price) path. Caller identity is set to owner.
func doRegister(cur realm, name string, owner address, duration int64) {
	secret := "sec-" + name
	canonical, err := Normalize(name)
	if err != nil {
		panic(err)
	}
	c := computeCommitment(canonical, owner, duration, secret, "", config.PolicyRevision)

	testing.SetRealm(testing.NewUserRealm(owner))
	Commit(cross(cur), c)

	testing.SkipHeights(3) // +15s > MinCommitAge (10s)

	testing.SetRealm(testing.NewUserRealm(owner))
	Register(cross(cur), RegisterRequest{
		Name:           name,
		Owner:          owner,
		Duration:       duration,
		Secret:         secret,
		PolicyRevision: config.PolicyRevision,
	})
}
