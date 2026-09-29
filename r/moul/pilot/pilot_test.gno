package pilot

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

var (
	// the address Claim is pinned to, not a test address
	moul    = address("g1manfred47kzduec920z88wfr64ylksmdcedlf5")
	someone = testutils.TestAddress("someone")
)

func TestClaimIsOnceAndOwnerGated(cur realm, t *testing.T) {
	// anyone else racing the deploy is refused, which is the whole point of
	// pinning the address in the source
	testing.SetRealm(testing.NewUserRealm(someone))
	uassert.AbortsContains(t, cur, "only g1manfred", func() { Claim(cross(cur)) })

	testing.SetRealm(testing.NewUserRealm(moul))
	Claim(cross(cur))
	uassert.Equal(t, moul.String(), acct.Owner().String())

	testing.SetRealm(testing.NewUserRealm(someone))
	uassert.AbortsContains(t, cur, "already claimed", func() { Claim(cross(cur)) })
	uassert.AbortsContains(t, cur, "not the owner", func() {
		Approve(cross(cur), "gno.land/r/x/nope/v0", "nope", false, 1)
	})

	testing.SetRealm(testing.NewUserRealm(moul))
	uassert.AbortsContains(t, cur, "[a-zA-Z0-9._/-]", func() {
		Approve(cross(cur), "gno.land/r/x/nope/v0", "pay|out", false, 1)
	})
}

func TestRender(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(moul))
	Approve(cross(cur), "gno.land/r/moul/x/pilotdemo/v0", "payout", false, 250)

	want := "# gno.land/r/moul/pilot/v0\n\n" +
		"| | |\n|---|---|\n" +
		"| owner | " + moul.String() + " |\n" +
		"| treasury | " + Address().String() + " |\n" +
		"| balance | 0 ugnot |\n\n" +
		"## powers\n\n" +
		"| path | grant | identity | state | left | runs | sub-treasury |\n" +
		"|---|---|---|---|---|---|---|\n" +
		"| `gno.land/r/moul/x/pilotdemo/v0` | purse | `gno.land/r/moul/pilot/v0#payout` | approved | 250 | 0 | 0 ugnot |\n"
	uassert.Equal(t, want, Render(""))
}
