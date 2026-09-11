package entity

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

// This package is an API sketch recovered from an unmerged upstream proposal:
// it declares the Entity abstraction and its user/realm refinements, but all
// three constructors are `panic("not implemented")`. The tests pin that surface
// so implementing one is a deliberate, visible change.

func TestConstructorsAreNotImplemented(cur realm, t *testing.T) {
	addr := testutils.TestAddress("alice")

	uassert.PanicsWithMessage(t, cur, "not implemented", func() { NewUserByAddr(addr) })
	uassert.PanicsWithMessage(t, cur, "not implemented", func() { NewUserByName("alice") })
}

// TestInterfacesAreDeclared is a compile-time check that the interface
// hierarchy still exists with its documented shape.
func TestInterfacesAreDeclared(t *testing.T) {
	var (
		_ Entity
		_ Kind
		_ UserEntity
		_ RealmEntity
	)
	uassert.True(t, true, "entity interfaces are declared")
}

// TestRefinementsEmbedEntity pins that UserEntity and RealmEntity are still
// refinements of Entity — assigning them to an Entity must compile.
func TestRefinementsEmbedEntity(t *testing.T) {
	var (
		u UserEntity
		r RealmEntity
	)
	var _ Entity = u
	var _ Entity = r
	uassert.True(t, true, "UserEntity and RealmEntity satisfy Entity")
}
