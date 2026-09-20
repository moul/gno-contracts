package capwallet

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

var (
	owner = testutils.TestAddress("owner")
	percy = testutils.TestAddress("percy")
	mallory = testutils.TestAddress("mallory")
)

func TestGrantAndExercise(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(owner))
	// Percy may call r/moul/issues.Assign, ≤5 GNOT, 2 times, no expiry.
	id := Grant(cross(cur), percy, "gno.land/r/moul/issues", "Assign", 5000000, 0, 2, "issue IDs 100-200")

	// Read-only gate other realms use.
	uassert.True(t, Authorized(id, percy, 5000000))
	uassert.False(t, Authorized(id, percy, 5000001)) // over ceiling
	uassert.False(t, Authorized(id, mallory, 1))      // wrong principal

	testing.SetRealm(testing.NewUserRealm(percy))
	Exercise(cross(cur), id, 3000000)
	uassert.Equal(t, uint32(1), Get(id).RemainingUses)
	Exercise(cross(cur), id, 1000000)
	uassert.Equal(t, uint32(0), Get(id).RemainingUses)

	// Exhausted.
	uassert.False(t, Authorized(id, percy, 1))
	uassert.AbortsWithMessage(t, cur, "capability exhausted", func(cur realm) {
		Exercise(cur, id, 1)
	})
}

func TestCeilingEnforced(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(owner))
	id := Grant(cross(cur), percy, "r/x", "F", 100, 0, 3, "")
	testing.SetRealm(testing.NewUserRealm(percy))
	uassert.AbortsWithMessage(t, cur, "coins 101 exceed capability ceiling 100", func(cur realm) {
		Exercise(cur, id, 101)
	})
}

func TestOnlyPrincipal(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(owner))
	id := Grant(cross(cur), percy, "r/x", "F", 100, 0, 3, "")
	testing.SetRealm(testing.NewUserRealm(mallory))
	uassert.AbortsWithMessage(t, cur, "caller is not the capability principal", func(cur realm) {
		Exercise(cur, id, 1)
	})
}

func TestRevoke(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(owner))
	id := Grant(cross(cur), percy, "r/x", "F", 100, 0, 3, "")

	// Only the granter may revoke.
	testing.SetRealm(testing.NewUserRealm(mallory))
	uassert.AbortsWithMessage(t, cur, "only the granter may revoke", func(cur realm) {
		Revoke(cur, id)
	})

	testing.SetRealm(testing.NewUserRealm(owner))
	Revoke(cross(cur), id)
	uassert.False(t, Authorized(id, percy, 1))
	testing.SetRealm(testing.NewUserRealm(percy))
	uassert.AbortsWithMessage(t, cur, "capability revoked", func(cur realm) {
		Exercise(cur, id, 1)
	})
}

func TestExpiry(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(owner))
	h := int64(0) // ChainHeight in tests starts at 0; set expiry in the past-ish
	_ = h
	// Grant valid only up to height 1.
	id := Grant(cross(cur), percy, "r/x", "F", 100, 1, 3, "")
	testing.SkipHeights(5) // now well past height 1
	uassert.False(t, Authorized(id, percy, 1))
	testing.SetRealm(testing.NewUserRealm(percy))
	uassert.AbortsWithMessage(t, cur, "capability expired", func(cur realm) {
		Exercise(cur, id, 1)
	})

	uassert.True(t, len(Render("")) > 0)
	uassert.True(t, len(Render("1")) > 0)
}
