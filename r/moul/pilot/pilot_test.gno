package pilot

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

var (
	owner   = testutils.TestAddress("owner")
	someone = testutils.TestAddress("someone")
)

func TestClaimIsOnceAndOwnerGated(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(owner))
	Claim(cross(cur))
	uassert.Equal(t, owner.String(), acct.Owner().String())

	testing.SetRealm(testing.NewUserRealm(someone))
	uassert.AbortsContains(t, cur, "already claimed", func() { Claim(cross(cur)) })
	uassert.AbortsContains(t, cur, "not the owner", func() {
		Approve(cross(cur), "gno.land/r/x/nope/v0", "nope", false, 1)
	})

	testing.SetRealm(testing.NewUserRealm(owner))
	uassert.AbortsContains(t, cur, "[a-zA-Z0-9._/-]", func() {
		Approve(cross(cur), "gno.land/r/x/nope/v0", "pay|out", false, 1)
	})
}

func TestRender(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(owner))
	Approve(cross(cur), "gno.land/r/moul/x/pilotdemo/v0", "payout", false, 250)

	want := "# gno.land/r/moul/pilot/v0\n\n" +
		"| | |\n|---|---|\n" +
		"| owner | " + owner.String() + " |\n" +
		"| treasury | " + Address().String() + " |\n" +
		"| balance | 0 ugnot |\n\n" +
		"## powers\n\n" +
		"| path | grant | identity | state | left | runs | sub-treasury |\n" +
		"|---|---|---|---|---|---|---|\n" +
		"| `gno.land/r/moul/x/pilotdemo/v0` | purse | `gno.land/r/moul/pilot/v0#payout` | approved | 250 | 0 | 0 ugnot |\n"
	uassert.Equal(t, want, Render(""))
}
