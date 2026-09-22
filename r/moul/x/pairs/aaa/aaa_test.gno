package aaa

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

func TestFaucetAndRender(cur realm, t *testing.T) {
	user := testutils.TestAddress("aaa-user")
	testing.SetRealm(testing.NewUserRealm(user))
	Faucet(cross(cur))
	uassert.Equal(t, int64(1_000_000_000), BalanceOf(user))

	uassert.True(t, strings.Contains(Render(""), "# AAA"))
	uassert.Equal(t, "gno.land/r/moul/x/pairs/aaa/v0.AAA", Key)
}
