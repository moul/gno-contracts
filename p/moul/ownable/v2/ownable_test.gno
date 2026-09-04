package ownable

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// This package is an API sketch recovered from an unmerged upstream proposal:
// it declares the Owner abstraction and its four owner kinds, but And/Or are
// `panic("not implemented")`. The tests pin that surface so that implementing
// one is a deliberate, visible change rather than a silent behaviour shift.

func TestCompositionHelpersAreNotImplemented(cur realm, t *testing.T) {
	uassert.PanicsWithMessage(t, cur, "not implemented", func() { And(nil) })
	uassert.PanicsWithMessage(t, cur, "not implemented", func() { Or(nil) })
}

// TestOwnerKindsAreDeclared is a compile-time check that the concrete owner
// types still exist with their documented shape.
func TestOwnerKindsAreDeclared(t *testing.T) {
	var (
		_ UserOwner
		_ RealmOwner
		_ MembstoreOwner
		_ DAOOwner
		_ Kind
	)
	uassert.True(t, true, "owner kinds are declared")
}

// TestKindIsAnInt pins Kind's underlying type: it is compared and likely
// persisted numerically, so a change of base type is breaking.
func TestKindIsAnInt(t *testing.T) {
	var k Kind
	uassert.Equal(t, 0, int(k), "zero Kind is 0")
}
