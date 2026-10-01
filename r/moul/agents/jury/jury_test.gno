package jury

import (
	"strings"
	"testing"

	"gno.land/p/moul/agents/commit/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/ufmt/v0"
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
	id := OpenCase(cross(cur), "receipt#7", j1.String()+","+j2.String()+", "+j3.String())
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
	id := OpenCase(cross(cur), "claim#3", j1.String())
	commitAs(cur, j1, id, true, "salt")

	testing.SetRealm(testing.NewUserRealm(j1))
	uassert.AbortsWithMessage(t, cur, "reveal does not match commitment", func(cur realm) {
		Reveal(cur, id, false, "salt") // flipped verdict
	})
}

func TestOnlyPanelJurors(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(opener))
	id := OpenCase(cross(cur), "x", j1.String())
	testing.SetRealm(testing.NewUserRealm(nobody))
	uassert.AbortsWithMessage(t, cur, "caller is not on this jury", func(cur realm) {
		Commit(cur, id, commit.Verdict(true, "s"))
	})
}

func TestNoDuplicateJurors(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(opener))
	uassert.AbortsWithMessage(t, cur, "duplicate juror: "+j1.String(), func(cur realm) {
		OpenCase(cur, "x", j1.String()+","+j1.String())
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

// Commitments are public, so a juror who copies another's hash would reveal
// the same (verdict, salt) once the first reveal lands. The copy is refused.
func TestCopiedCommitmentIsRefused(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(opener))
	id := OpenCase(cross(cur), "copy", j1.String()+","+j2.String())
	commitAs(cur, j1, id, true, "s1")
	copied := Get(id).Jurors[0].Commitment
	testing.SetRealm(testing.NewUserRealm(j2))
	uassert.AbortsContains(t, cur, "commitment already used", func() { Commit(cross(cur), id, copied) })
}

// The panel arrives as one string, which is what a wallet can send.
func TestOpenCaseRejectsAnInvalidJuror(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(opener))
	uassert.AbortsContains(t, cur, "invalid juror address", func() {
		OpenCase(cross(cur), "x", j1.String()+",notanaddress")
	})
	uassert.AbortsContains(t, cur, "invalid juror address", func() { OpenCase(cross(cur), "x", "") })
}

// The subject is wallet-controlled now that OpenCase is callable, so it is
// escaped on both pages that show it.
func TestSubjectIsEscaped(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(opener))
	id := OpenCase(cross(cur), "x | [claim](https://evil.example)", j1.String())
	idx, page := Render(""), Render(ufmt.Sprintf("%d", id))
	uassert.False(t, strings.Contains(idx, "[claim](https://evil.example)"), idx)
	uassert.False(t, strings.Contains(page, "[claim](https://evil.example)"), page)
}
