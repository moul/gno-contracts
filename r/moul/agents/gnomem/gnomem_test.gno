package gnomem

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

var (
	researcher = testutils.TestAddress("researcher")
	skeptic    = testutils.TestAddress("skeptic")
	judge      = testutils.TestAddress("judge")
)

// The canonical scenario from the design: a researcher proposes, a skeptic
// contests with an exploit, an adjudicator supersedes with the corrected
// claim.
func TestContestedThenSuperseded(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(researcher))
	id := ProposeClaim(cross(cur), "foo/v2", "is", "safe to deploy", "report#H1", 82)
	uassert.Equal(t, uint64(1), id)
	uassert.Equal(t, string(StatusProposed), string(Get(id).Status))

	// Skeptic contests with a refutation.
	testing.SetRealm(testing.NewUserRealm(skeptic))
	ContestClaim(cross(cur), id, "unbounded allocation", "exploit#H2")
	uassert.Equal(t, string(StatusContested), string(Get(id).Status))
	uassert.True(t, IsOpen(id))

	// Adjudicator supersedes with the corrected claim.
	testing.SetRealm(testing.NewUserRealm(judge))
	newID := SupersedeClaim(cross(cur), id, "foo/v2", "is", "unsafe before commit abc123", "report#H3", 95)
	uassert.Equal(t, uint64(2), newID)

	old := Get(id)
	uassert.Equal(t, string(StatusSuperseded), string(old.Status))
	uassert.Equal(t, newID, old.SupersededBy)
	uassert.False(t, IsOpen(id)) // superseded is terminal

	newC := Get(newID)
	uassert.Equal(t, id, newC.Supersedes)
	uassert.Equal(t, 1, len(newC.Evidence)) // the initial report#H3

	uassert.True(t, len(Render("")) > 0)
	uassert.True(t, len(Render("1")) > 0)
	uassert.True(t, len(Render("2")) > 0)
}

func TestSupportThenAccept(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(researcher))
	id := ProposeClaim(cross(cur), "gnovm", "supports", "persistent object graphs", "", 90)

	testing.SetRealm(testing.NewUserRealm(skeptic))
	SupportClaim(cross(cur), id, 88, "confirmed in docs")
	uassert.Equal(t, string(StatusSupported), string(Get(id).Status))

	testing.SetRealm(testing.NewUserRealm(judge))
	ResolveClaim(cross(cur), id, true)
	uassert.Equal(t, string(StatusAccepted), string(Get(id).Status))
	uassert.False(t, IsOpen(id))
}

func TestCannotMutateTerminal(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(researcher))
	id := ProposeClaim(cross(cur), "x", "is", "y", "", 50)
	ResolveClaim(cross(cur), id, false) // retracted, terminal

	uassert.AbortsWithMessage(t, cur, "claim is resolved (terminal): retracted", func(cur realm) {
		SupportClaim(cur, id, 10, "too late")
	})
}

func TestBadInputs(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(researcher))
	uassert.AbortsWithMessage(t, cur, "empty triple field", func(cur realm) {
		ProposeClaim(cur, "", "is", "y", "", 10)
	})
	uassert.AbortsWithMessage(t, cur, "confidence must be 0..100", func(cur realm) {
		ProposeClaim(cur, "a", "b", "c", "", 200)
	})
}
