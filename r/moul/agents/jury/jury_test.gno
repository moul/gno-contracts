package jury

import (
	"testing"

	"gno.land/p/moul/agents/commit/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

var (
	opener = testutils.TestAddress("opener")
	j1     = testutils.TestAddress("juror1")
	j2     = testutils.TestAddress("juror2")
	j3     = testutils.TestAddress("juror3")
	nobody = testutils.TestAddress("nobody")
)

// Full happy path: 3 jurors commit blind, then reveal; majority upholds.
func TestCommitRevealMajority(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(opener))
	id := OpenCase(cross(cur), "receipt#7", []address{j1, j2, j3})
	uassert.Equal(t, string(PhaseCommit), string(Get(id).Phase))

	// Each juror commits a hidden verdict (hash computed off-chain).
	commitAs(cur, j1, id, true, "s1")
	commitAs(cur, j2, id, false, "s2")
	uassert.Equal(t, string(PhaseCommit), string(Get(id).Phase)) // not all in yet
	commitAs(cur, j3, id, true, "s3")
	uassert.Equal(t, string(PhaseReveal), string(Get(id).Phase)) // auto-advanced

	revealAs(cur, j1, id, true, "s1")
	revealAs(cur, j2, id, false, "s2")
	revealAs(cur, j3, id, true, "s3")

	c := Get(id)
	uassert.Equal(t, string(PhaseClosed), string(c.Phase))
	uassert.Equal(t, "upheld", c.Outcome) // 2 yes vs 1 no
	uassert.Equal(t, 2, c.Yes)
	uassert.Equal(t, 1, c.No)

	uassert.True(t, len(Render("")) > 0)
	uassert.True(t, len(Render("1")) > 0)
}

// A juror cannot change their vote at reveal time: the commitment binds it.
func TestRevealMustMatchCommitment(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(opener))
	id := OpenCase(cross(cur), "claim#3", []address{j1})
	commitAs(cur, j1, id, true, "salt")

	testing.SetRealm(testing.NewUserRealm(j1))
	uassert.AbortsWithMessage(t, cur, "reveal does not match commitment", func(cur realm) {
		Reveal(cur, id, false, "salt") // flipped verdict
	})
}

func TestOnlyPanelJurors(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(opener))
	id := OpenCase(cross(cur), "x", []address{j1})
	testing.SetRealm(testing.NewUserRealm(nobody))
	uassert.AbortsWithMessage(t, cur, "caller is not on this jury", func(cur realm) {
		Commit(cur, id, commit.Verdict(true, "s"))
	})
}

func TestNoDuplicateJurors(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(opener))
	uassert.AbortsWithMessage(t, cur, "duplicate juror: "+j1.String(), func(cur realm) {
		OpenCase(cur, "x", []address{j1, j1})
	})
}

// helpers

func commitAs(cur realm, juror address, id uint64, verdict bool, salt string) {
	testing.SetRealm(testing.NewUserRealm(juror))
	Commit(cross(cur), id, commit.Verdict(verdict, salt))
}

func revealAs(cur realm, juror address, id uint64, verdict bool, salt string) {
	testing.SetRealm(testing.NewUserRealm(juror))
	Reveal(cross(cur), id, verdict, salt)
}
