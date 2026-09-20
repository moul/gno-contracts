package grc20faucet

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/r/nt/grc20reg/v0"
)

// testing.SetRealm governs the crossing calls made from the frame that called
// it, so switching accounts has to be written inline in each test, never
// through a helper that does not itself cross.
func TestClaimAndCooldown(cur realm, t *testing.T) {
	alice := testutils.TestAddress("f-alice")
	testing.SetRealm(testing.NewUserRealm(alice))

	_, ok := NextClaim(alice)
	uassert.False(t, ok, "no cooldown before the first claim")

	Claim(cross(cur))
	uassert.Equal(t, ClaimAmount, BalanceOf("RED", alice))
	uassert.Equal(t, ClaimAmount, BalanceOf("BLUE", alice))

	next, ok := NextClaim(alice)
	uassert.True(t, ok, "a cooldown is recorded")
	uassert.AbortsContains(t, cur, "too soon", func() { Claim(cross(cur)) })

	testing.SkipHeights(ClaimEvery + 1)
	Claim(cross(cur))
	uassert.Equal(t, 2*ClaimAmount, BalanceOf("RED", alice))

	after, _ := NextClaim(alice)
	uassert.True(t, after > next, "the cooldown moved forward")
}

func TestTransferAndAllowance(cur realm, t *testing.T) {
	alice := testutils.TestAddress("f-tx-alice")
	bob := testutils.TestAddress("f-tx-bob")
	carl := testutils.TestAddress("f-tx-carl")

	testing.SetRealm(testing.NewUserRealm(alice))
	Claim(cross(cur))
	Transfer(cross(cur), "RED", bob, 400_000)
	uassert.Equal(t, int64(400_000), BalanceOf("RED", bob))
	uassert.Equal(t, ClaimAmount-400_000, BalanceOf("RED", alice))

	Approve(cross(cur), "BLUE", carl, 250_000)
	uassert.Equal(t, int64(250_000), Allowance("BLUE", alice, carl))

	testing.SetRealm(testing.NewUserRealm(carl))
	TransferFrom(cross(cur), "BLUE", alice, bob, 250_000)
	uassert.Equal(t, int64(250_000), BalanceOf("BLUE", bob))
	uassert.Equal(t, int64(0), Allowance("BLUE", alice, carl))
	uassert.AbortsContains(t, cur, "insufficient allowance", func() {
		TransferFrom(cross(cur), "BLUE", alice, bob, 1)
	})
}

func TestUnknownSymbolIsRefused(cur realm, t *testing.T) {
	who := testutils.TestAddress("f-unknown")
	testing.SetRealm(testing.NewUserRealm(who))

	uassert.PanicsContains(t, cur, "unknown symbol GREEN", func() {
		BalanceOf("GREEN", who)
	})
	uassert.AbortsContains(t, cur, "unknown symbol GREEN", func() {
		Transfer(cross(cur), "GREEN", who, 1)
	})
}

// Both tokens are in the registry under their own realm and symbol, which is
// what lets another realm move them without importing this one.
func TestBothTokensAreRegistered(t *testing.T) {
	uassert.Equal(t, "gno.land/r/moul/x/grc20faucet/v0.RED", RedKey)
	uassert.Equal(t, "gno.land/r/moul/x/grc20faucet/v0.BLUE", BlueKey)
	uassert.Equal(t, "Red Token", grc20reg.MustGet(RedKey).GetName())
	uassert.Equal(t, "Blue Token", grc20reg.MustGet(BlueKey).GetName())
	uassert.Equal(t, 4, grc20reg.MustGet(BlueKey).GetDecimals())
}

func TestRender(cur realm, t *testing.T) {
	who := testutils.TestAddress("f-render")
	testing.SetRealm(testing.NewUserRealm(who))
	Claim(cross(cur))

	home := Render("")
	uassert.True(t, strings.Contains(home, "# GRC20 faucet: RED and BLUE"), home)
	uassert.True(t, strings.Contains(home, "| Red Token | RED | 4 |"), home)
	uassert.True(t, strings.Contains(home, RedKey), "the registry key is discoverable")

	page := Render(who.String())
	uassert.True(t, strings.Contains(page, "Balance of"), page)
	uassert.True(t, strings.Contains(page, "RED 1000000"), page)
}
