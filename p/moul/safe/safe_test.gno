package safe

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

// This package is a design sketch: only the constructor and the four read
// accessors are implemented, and every proposal method is `panic("not
// implemented")`. The tests below pin the implemented behaviour and pin the
// stubs as stubs, so implementing one is a deliberate, visible change.

var alice = testutils.TestAddress("alice")

// NewSafe reads unsafe.PreviousRealm(), which needs a real realm frame: a user
// realm gives "frame not found: cannot seek beyond origin caller override".
func TestNewSafeDefaults(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/test/safeone"))
	s := NewSafe()

	uassert.Equal(t, "", s.Name(), "a fresh safe is unnamed")
	uassert.Equal(t, uint(1), s.Threshold(), "threshold starts at 1")
	uassert.Equal(t, uint(1), s.Size(), "the creator is the only member")
	uassert.Equal(t, 1, len(s.Members()))
	uassert.True(t, s.Members()[0].IsValid(), "the sole member is a valid address")
}

// Note: caller-sensitivity of NewSafe is NOT asserted here. From a `p/` test
// package there is a single realm frame, so unsafe.PreviousRealm() resolves to
// the origin no matter what testing.SetRealm is given — two different code
// realms seed the identical address. Proving "membership follows the caller"
// needs an `r/` test package that can actually cross into this one.

func TestSizeTracksMembers(t *testing.T) {
	s := safe{members: []address{alice, testutils.TestAddress("bob")}, threshold: 2}
	uassert.Equal(t, uint(2), s.Size())
	uassert.Equal(t, uint(2), s.Threshold())
}

// TestUnimplementedMethodsPanic documents the sketch surface. If one of these
// starts working, this test fails and forces the contract change to be noticed.
func TestUnimplementedMethodsPanic(cur realm, t *testing.T) {
	s := safe{members: []address{alice}, threshold: 1}

	uassert.PanicsWithMessage(t, cur, "not implemented", func() { s.NextProposal() })
	uassert.PanicsWithMessage(t, cur, "not implemented", func() { s.UpcomingProposals(0) })
	uassert.PanicsWithMessage(t, cur, "not implemented", func() { s.PreviousProposals(0) })
	uassert.PanicsWithMessage(t, cur, "not implemented", func() { s.ProposeAddingMember(alice, 1) })
	uassert.PanicsWithMessage(t, cur, "not implemented", func() { s.ProposeRemovingMember(alice, 1) })
	uassert.PanicsWithMessage(t, cur, "not implemented", func() { s.ProposeUpdatingThreshold(2) })
	uassert.PanicsWithMessage(t, cur, "not implemented", func() { s.GetProposal(0) })
	uassert.PanicsWithMessage(t, cur, "not implemented", func() { s.ApproveProposal(nil) })
	uassert.PanicsWithMessage(t, cur, "not implemented", func() { s.ExecuteProposal(nil) })
	uassert.PanicsWithMessage(t, cur, "not implemented", func() { s.CancelProposal(nil) })
	uassert.PanicsWithMessage(t, cur, "not implemented", func() { s.Render("") })
}

// TestSafeSatisfiesInterface is a compile-time check that the concrete type
// still implements the exported interface.
func TestSafeSatisfiesInterface(t *testing.T) {
	var _ Safe = safe{}
	uassert.True(t, true, "safe implements Safe")
}
