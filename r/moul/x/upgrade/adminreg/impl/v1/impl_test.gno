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
// by the time this runs — and neither is serving.
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

	uassert.Equal(t, "adminreg/facade/v0\n"+
		"live: impl/v1 (gno.land/r/moul/x/upgrade/adminreg/impl/v1)\n"+
		"HELLO, world!\n"+
		"candidates: 2\n"+
		"- gno.land/r/moul/x/upgrade/adminreg/impl/v0\n"+
		"- gno.land/r/moul/x/upgrade/adminreg/impl/v1\n", facade.Render(""))
}
