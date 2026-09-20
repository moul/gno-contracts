package maintainer

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

var (
	bot = testutils.TestAddress("maintainerbot")
	rev1 = testutils.TestAddress("rev1")
	rev2 = testutils.TestAddress("rev2")
)

func TestPolicyGate(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(bot))
	id := Propose(cross(cur), "v2", "artifact#H", 3) // 3-block challenge window

	// Approval blocked: no tests, no reviews, window open.
	uassert.AbortsWithMessage(t, cur, "policy: tests have not passed", func(cur realm) {
		Approve(cur, id)
	})

	AttestTests(cross(cur), id, true)
	uassert.AbortsWithMessage(t, cur, "policy: need 2 reviews, have 0", func(cur realm) {
		Approve(cur, id)
	})

	// One low review blocks on the min-score rule.
	testing.SetRealm(testing.NewUserRealm(rev1))
	AddReview(cross(cur), id, 90, "looks good")
	testing.SetRealm(testing.NewUserRealm(rev2))
	AddReview(cross(cur), id, 70, "concerns")
	testing.SetRealm(testing.NewUserRealm(bot))
	uassert.AbortsWithMessage(t, cur, "policy: review from "+short(rev2)+" scored 70 < 80", func(cur realm) {
		Approve(cur, id)
	})
}

func TestFullApprovalPath(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(bot))
	id := Propose(cross(cur), "v3", "artifact#H3", 2)
	AttestTests(cross(cur), id, true)

	testing.SetRealm(testing.NewUserRealm(rev1))
	AddReview(cross(cur), id, 85, "ok")
	testing.SetRealm(testing.NewUserRealm(rev2))
	AddReview(cross(cur), id, 95, "great")

	// Challenge window still open -> blocked.
	testing.SetRealm(testing.NewUserRealm(bot))
	uassert.AbortsWithMessage(t, cur, "policy: challenge window still open", func(cur realm) {
		Approve(cur, id)
	})

	testing.SkipHeights(10)
	Approve(cross(cur), id)
	uassert.True(t, GetProposal(id).Approved)
	uassert.Equal(t, "v3", LatestVersion())

	// Deprecate it.
	Deprecate(cross(cur), "v3", "CVE-xyz")
	uassert.True(t, IsDeprecated("v3"))

	uassert.True(t, len(Render("")) > 0)
	uassert.True(t, len(Render("1")) > 0)
}

func TestProposerCannotReview(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(bot))
	id := Propose(cross(cur), "v4", "a#4", 0)
	uassert.AbortsWithMessage(t, cur, "proposer cannot review own proposal", func(cur realm) {
		AddReview(cur, id, 100, "self five")
	})
}
