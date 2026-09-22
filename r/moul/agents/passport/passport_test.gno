package passport

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

var (
	alice = testutils.TestAddress("alice")
	bob   = testutils.TestAddress("bob")
	carol = testutils.TestAddress("carol")
)

func TestLifecycle(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	Register(cross(cur), "percy", "claude-opus-4-8@abc123")

	uassert.True(t, Exists("percy"))
	uassert.True(t, IsActive("percy"))
	uassert.True(t, IsOperator("percy", alice))
	uassert.False(t, IsOperator("percy", bob))
	uassert.Equal(t, 1, Count())

	// Owner adds an operator; the operator now passes the gate.
	AddOperator(cross(cur), "percy", bob)
	uassert.True(t, IsOperator("percy", bob))

	// A runtime change is recorded as drift.
	SetRuntime(cross(cur), "percy", "claude-opus-4-8@def456")
	a := Get("percy")
	uassert.Equal(t, "claude-opus-4-8@def456", a.Runtime)

	// Suspending drops the operator gate for everyone.
	Suspend(cross(cur), "percy")
	uassert.False(t, IsActive("percy"))
	uassert.False(t, IsOperator("percy", alice))
	Reactivate(cross(cur), "percy")
	uassert.True(t, IsActive("percy"))

	// Render must not panic and must mention the agent.
	uassert.True(t, len(Render("")) > 0)
	uassert.True(t, strings.Contains(Render("percy"), "percy"))
}

func TestOwnershipGate(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	Register(cross(cur), "gate", "rt")

	// bob is not the owner and cannot mutate.
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsWithMessage(t, cur, "caller is not the owner of gate", func(cur realm) {
		SetRuntime(cur, "gate", "hacked")
	})

	// Transfer to carol, then carol controls it.
	testing.SetRealm(testing.NewUserRealm(alice))
	Transfer(cross(cur), "gate", carol)
	testing.SetRealm(testing.NewUserRealm(carol))
	SetRuntime(cross(cur), "gate", "carol-rt")
	uassert.Equal(t, "carol-rt", Get("gate").Runtime)
}

func TestDuplicateRegister(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	Register(cross(cur), "dup", "rt")
	uassert.AbortsWithMessage(t, cur, "agent id already registered: dup", func(cur realm) {
		Register(cur, "dup", "rt")
	})
}

func TestRetireIsTerminal(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(alice))
	Register(cross(cur), "term", "rt")
	Retire(cross(cur), "term")
	uassert.AbortsWithMessage(t, cur, "retired agents cannot be reactivated", func(cur realm) {
		Reactivate(cur, "term")
	})
}
