package bbb

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

func TestFaucetAndRender(cur realm, t *testing.T) {
	user := testutils.TestAddress("bbb-user")
	testing.SetRealm(testing.NewUserRealm(user))
	Faucet(cross(cur))
	uassert.Equal(t, int64(1_000_000_000), BalanceOf(user))

	uassert.True(t, strings.Contains(Render(""), "# BBB"))
	uassert.Equal(t, "gno.land/r/moul/x/pairs/bbb/v0.BBB", Key)
}
