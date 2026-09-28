package impl

import (
	"testing"

	facade "gno.land/r/moul/x/upgrade/adminreg/facade/v0"
	implv0 "gno.land/r/moul/x/upgrade/adminreg/impl/v0"

	"gno.land/p/nt/uassert/v0"
)

// TestProposeThenAccept checks the two-step shape: deploying nominates, and
// only an owner transaction naming a path promotes it.
//
// Both impl realms are imported here, so both have already nominated themselves
// by the time this runs, and neither is serving.
func TestProposeThenAccept(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(facade.Ownable.Owner()))

	uassert.Equal(t, 2, len(facade.Candidates()), "both versions nominated themselves")
	uassert.Equal(t, "", facade.Live(), "nominating is not serving")
	uassert.AbortsContains(t, cur, "no implementation accepted", func() {
		facade.Greet("world")
	})

	// Accepting names a path, not an object: this is a plain maketx call.
	facade.Accept(cross(cur), "gno.land/r/moul/x/upgrade/adminreg/impl/v0")
	uassert.Equal(t, "impl/v0", facade.Version())
	uassert.Equal(t, "hello, world", facade.Greet("world"))

	// The upgrade, and the rollback, are the same single call.
	facade.Accept(cross(cur), "gno.land/r/moul/x/upgrade/adminreg/impl/v1")
	uassert.Equal(t, "HELLO, world!", facade.Greet("world"))
	facade.Accept(cross(cur), implv0.Path)
	uassert.Equal(t, "hello, world", facade.Greet("world"))
	facade.Accept(cross(cur), Path)

	// A path nobody nominated cannot be accepted, however owned you are.
	uassert.AbortsContains(t, cur, "no candidate at", func() {
		facade.Accept(cross(cur), "gno.land/r/moul/x/upgrade/adminreg/impl/v9")
	})

	// A non-owner cannot accept even a legitimate candidate.
	testing.SetRealm(testing.NewUserRealm("g1w4ek2u33ta047h6lta047h6lta047h6ldvdwpn"))
	uassert.AbortsContains(t, cur, "caller is not owner", func() {
		facade.Accept(cross(cur), implv0.Path)
	})

	uassert.Equal(t, "adminreg/facade/v0 [open]\n"+
		"live: impl/v1 (gno.land/r/moul/x/upgrade/adminreg/impl/v1)\n"+
		"HELLO, world!\n"+
		"candidates: 2\n"+
		"- gno.land/r/moul/x/upgrade/adminreg/impl/v0\n"+
		"- gno.land/r/moul/x/upgrade/adminreg/impl/v1\n", facade.Render(""))
}

// TestDispatchCost100 does 100 dispatches through this pattern's entry point,
// so `gno test -print-runtime-metrics` prints a cycle count for a known
// workload. Its twin is TestDispatchCost100 in schema/impl/gen1.
//
func TestDispatchCost100(cur realm, t *testing.T) {
	// Runs after TestProposeThenAccept, which leaves v1 live, and before
	// TestLadder, which freezes. Reads only, so it disturbs neither.
	for i := 0; i < 100; i++ {
		facade.Greet("world")
	}
	uassert.Equal(t, "HELLO, world!", facade.Greet("world"))
}

// TestLadder walks the three rungs and checks the ratchet refuses to loosen.
//
// Runs after TestProposeThenAccept on purpose: every rung is one-way, so the
// tests that need to propose and accept freely must already have run.
func TestLadder(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(facade.Ownable.Owner()))
	uassert.Equal(t, facade.StageOpen, facade.Stage())

	// Rung 2: no new code, but rolling back among what exists still works.
	facade.Close(cross(cur))
	uassert.Equal(t, facade.StageClosed, facade.Stage())
	uassert.AbortsContains(t, cur, "no new candidate may be proposed", func() {
		Propose(cross(cur))
	})
	facade.Accept(cross(cur), implv0.Path)
	uassert.Equal(t, "hello, world", facade.Greet("world"), "rollback survives Close")
	facade.Accept(cross(cur), Path)

	// The ratchet only turns one way, even for the owner.
	uassert.AbortsContains(t, cur, "only tightens", func() {
		facade.Close(cross(cur))
	})

	// Rung 3: nothing is accepted again.
	facade.Freeze(cross(cur))
	uassert.Equal(t, facade.StageFrozen, facade.Stage())
	uassert.AbortsContains(t, cur, "is frozen", func() {
		facade.Accept(cross(cur), implv0.Path)
	})
	uassert.AbortsContains(t, cur, "only tightens", func() {
		facade.Freeze(cross(cur))
	})

	// What was live stays live, and the render says which rung it is on.
	uassert.Equal(t, "HELLO, world!", facade.Greet("world"))
	uassert.Equal(t, "adminreg/facade/v0 [frozen]\n"+
		"live: impl/v1 (gno.land/r/moul/x/upgrade/adminreg/impl/v1)\n"+
		"HELLO, world!\n"+
		"candidates: 2\n"+
		"- gno.land/r/moul/x/upgrade/adminreg/impl/v0\n"+
		"- gno.land/r/moul/x/upgrade/adminreg/impl/v1\n", facade.Render(""))
}
