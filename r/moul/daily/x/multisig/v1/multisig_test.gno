package multisig

import (
	"strings"
	"testing"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

// reset clears package state between tests so each test is independent.
func reset() {
	owners = nil
	proposals = nil
	ownerCount = 0
	threshold = 0
	initialized = false
	nextID = 0
	owners = avl.NewTree()
	proposals = avl.NewTree()
}

func TestSetupAndPropose(cur realm, t *testing.T) {
	reset()

	a := testutils.TestAddress("alice")
	b := testutils.TestAddress("bob")
	c := testutils.TestAddress("carol")
	csv := a.String() + "," + b.String() + "," + c.String()

	testing.SetRealm(testing.NewUserRealm(a))
	Setup(cross(cur), csv, 2)

	uassert.True(t, initialized, "should be initialized")
	uassert.Equal(t, 3, ownerCount)
	uassert.Equal(t, 2, threshold)

	// alice (an owner) proposes
	testing.SetRealm(testing.NewUserRealm(a))
	id := Propose(cross(cur), "send funds to treasury")
	uassert.Equal(t, 0, id)

	// a non-owner cannot propose
	dave := testutils.TestAddress("dave")
	testing.SetRealm(testing.NewUserRealm(dave))
	uassert.AbortsWithMessage(t, cur, errNotOwner.Error(), func() {
		Propose(cross(cur), "sneaky proposal")
	})
}

func TestApproveReachesThreshold(cur realm, t *testing.T) {
	reset()

	a := testutils.TestAddress("alice")
	b := testutils.TestAddress("bob")
	c := testutils.TestAddress("carol")
	csv := a.String() + "," + b.String() + "," + c.String()

	testing.SetRealm(testing.NewUserRealm(a))
	Setup(cross(cur), csv, 2)

	testing.SetRealm(testing.NewUserRealm(a))
	id := Propose(cross(cur), "upgrade contract")

	// first approval: still pending
	testing.SetRealm(testing.NewUserRealm(a))
	Approve(cross(cur), id)
	v := proposals.Get("0")
	p := v.(*proposal)
	uassert.Equal(t, statePending.String(), p.state.String())
	uassert.Equal(t, 1, p.approvals.Size())

	// duplicate approval by same owner aborts
	testing.SetRealm(testing.NewUserRealm(a))
	uassert.AbortsWithMessage(t, cur, errDupApproval.Error(), func() {
		Approve(cross(cur), id)
	})

	// second distinct approval hits threshold -> executed
	testing.SetRealm(testing.NewUserRealm(b))
	Approve(cross(cur), id)
	uassert.Equal(t, stateExecuted.String(), p.state.String())
	uassert.Equal(t, 2, p.approvals.Size())

	// approving an executed proposal aborts
	testing.SetRealm(testing.NewUserRealm(c))
	uassert.AbortsWithMessage(t, cur, errExecuted.Error(), func() {
		Approve(cross(cur), id)
	})
}

func TestRenderShows(cur realm, t *testing.T) {
	reset()

	a := testutils.TestAddress("alice")
	b := testutils.TestAddress("bob")
	csv := a.String() + "," + b.String()

	testing.SetRealm(testing.NewUserRealm(a))
	Setup(cross(cur), csv, 2)

	testing.SetRealm(testing.NewUserRealm(a))
	Propose(cross(cur), "hello world")

	out := Render("")
	uassert.True(t, strings.Contains(out, "Threshold:"), "render shows threshold")
	uassert.True(t, strings.Contains(out, "2 of 2"), "render shows M-of-N")
	uassert.True(t, strings.Contains(out, "hello world"), "render shows proposal description")
	uassert.True(t, strings.Contains(out, "Pending"), "render shows state")
}
