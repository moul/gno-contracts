package impl

import (
	"testing"

	facade "gno.land/r/moul/x/upgrade/selfreg/facade/v0"
	implv0 "gno.land/r/moul/x/upgrade/selfreg/impl/v0"

	"gno.land/p/nt/uassert/v0"
)

// TestTakeoverOnDeploy checks that the last implementation to run its init owns
// the facade, and that re-registering an older one rolls the behaviour back.
//
// Both impl realms are imported here, so both inits have already run by the
// time this test starts; v1 is imported last and therefore holds the facade.
func TestTakeoverOnDeploy(cur realm, t *testing.T) {
	uassert.Equal(t, "gno.land/r/moul/x/upgrade/selfreg/impl/v1", facade.Live())
	uassert.Equal(t, "impl/v1", facade.Version())
	uassert.Equal(t, "HELLO, world!", facade.Greet("world"))

	// Rolling back is the same one call: the facade only ever holds a pointer.
	implv0.Register(cross(cur))
	uassert.Equal(t, "gno.land/r/moul/x/upgrade/selfreg/impl/v0", facade.Live())
	uassert.Equal(t, "hello, world", facade.Greet("world"))

	// And forward again.
	Register(cross(cur))
	uassert.Equal(t, "impl/v1", facade.Version())
	uassert.Equal(t, "selfreg/facade/v0 [open]: impl/v1 (gno.land/r/moul/x/upgrade/selfreg/impl/v1)\nHELLO, world!\n", facade.Render(""))
}

// TestSeal ends the realm's upgradeability and checks that it is terminal.
//
// Runs after TestTakeoverOnDeploy on purpose: sealing is one-way, so every test
// that needs to register must already have run.
func TestSeal(cur realm, t *testing.T) {
	// The live implementation is the only actor that may seal, because with no
	// owner it is the only one the facade already trusts.
	uassert.Equal(t, "gno.land/r/moul/x/upgrade/selfreg/impl/v1", facade.Live())
	uassert.Equal(t, facade.StageOpen, facade.Stage())
	uassert.AbortsContains(t, cur, "only the live implementation may seal", func() {
		implv0.Seal(cross(cur))
	})

	Seal(cross(cur))
	uassert.Equal(t, facade.StageSealed, facade.Stage())

	// Nothing registers again, not even the implementation that sealed it.
	uassert.AbortsContains(t, cur, "is sealed", func() {
		Register(cross(cur))
	})
	uassert.AbortsContains(t, cur, "is sealed", func() {
		implv0.Register(cross(cur))
	})

	// What was live stays live, and says so.
	uassert.Equal(t, "HELLO, world!", facade.Greet("world"))
	uassert.Equal(t, "selfreg/facade/v0 [sealed]: impl/v1 (gno.land/r/moul/x/upgrade/selfreg/impl/v1)\nHELLO, world!\n", facade.Render(""))
}
