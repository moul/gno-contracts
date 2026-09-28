package lazy

import (
	"testing"

	v0 "gno.land/r/moul/x/upgrade/lazy/v0"

	"gno.land/p/nt/uassert/v0"
)

// TestLazyMigration walks a record from v0 into v1 on first touch and checks
// what the two halves of the read path report on either side of it.
func TestLazyMigration(cur realm, t *testing.T) {
	uassert.Equal(t, 1, Migrated(), "only v1's own seed has moved")
	uassert.Equal(t, 2, Pending(), "both v0 records are untouched")

	// Peek converts without storing: the answer is right, the state is not moved.
	uassert.Equal(t, "v1{ada-migrated 1000 true}", Peek("ada").String())
	uassert.Equal(t, 1, Migrated(), "Peek must not migrate")

	// Get migrates.
	uassert.Equal(t, "v1{ada-migrated 1000 true}", Get(cross(cur), "ada").String())
	uassert.Equal(t, 2, Migrated(), "ada has moved over")
	uassert.Equal(t, 1, Pending())

	// Migrating COPIES: v0 still holds (and still pays for) the original.
	uassert.Equal(t, 2, v0.Size(), "v0 never shrinks")
	uassert.Equal(t, "v0{ada 1}", v0.Get("ada").String())

	// A second Get is a plain hit, not a second migration.
	uassert.Equal(t, "v1{ada-migrated 1000 true}", Get(cross(cur), "ada").String())
	uassert.Equal(t, 2, Migrated())

	// A key in neither version is nil in both halves.
	uassert.True(t, Get(cross(cur), "zoe") == nil)
	uassert.True(t, Peek("zoe") == nil)

	// v1's own records are untouched by any of this.
	uassert.Equal(t, "v1{cyd 3000 true}", Get(cross(cur), "cyd").String())

	uassert.Equal(t, "lazy/v1: 2 migrated, 1 pending in v0\n"+
		"- ada: v1{ada-migrated 1000 true}\n"+
		"- cyd: v1{cyd 3000 true}\n", Render(""))
}
