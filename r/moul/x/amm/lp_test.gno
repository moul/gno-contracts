package amm

import (
	"testing"

	"gno.land/p/nt/grc20/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/r/nt/grc20reg/v0"
)

// A third token, so a second pool can prove each one mints its own LP token.
var (
	tokCCC *grc20.Token
	ledCCC *grc20.PrivateLedger
	keyCCC string
)

func init(cur realm) {
	tokCCC, ledCCC = grc20.NewToken("Test Gamma", "CCC", 6, 2, cur)
	keyCCC = grc20reg.Register(cross(cur), tokCCC, "")
}

// TestLPPositionIsARealToken is the whole point of v1: the position exists
// outside this realm, as an ordinary registered GRC20.
func TestLPPositionIsARealToken(cur realm, t *testing.T) {
	reset()
	alice := testutils.TestAddress("lp-alice")
	fund(alice, 10_000_000)
	testing.SetRealm(testing.NewUserRealm(alice))
	minted := AddLiquidity(cross(cur), keyAAA, keyBBB, 1_000_000, 4_000_000)

	// Readable by any realm that knows the key, without importing this one.
	lp := grc20reg.MustGet(LPToken(keyAAA, keyBBB))
	uassert.Equal(t, minted, lp.BalanceOf(alice))
	uassert.Equal(t, minted, lp.TotalSupply())
	uassert.Equal(t, minted, TotalShares(keyAAA, keyBBB))
	// The LP unit is token A at seed time, so it mirrors token A's decimals.
	uassert.Equal(t, tokAAA.GetDecimals(), lp.GetDecimals())
	uassert.Equal(t, "AMM LP AAA/BBB", lp.GetName())
}

// TestLPIsTransferable: a position can change hands without touching the pool.
func TestLPIsTransferable(cur realm, t *testing.T) {
	reset()
	alice := testutils.TestAddress("xfer-alice")
	bob := testutils.TestAddress("xfer-bob")
	fund(alice, 10_000_000)

	testing.SetRealm(testing.NewUserRealm(alice))
	AddLiquidity(cross(cur), keyAAA, keyBBB, 1_000_000, 4_000_000)
	TransferLP(cross(cur), keyAAA, keyBBB, bob, 500_000)

	uassert.Equal(t, int64(500_000), SharesOf(keyAAA, keyBBB, alice))
	uassert.Equal(t, int64(500_000), SharesOf(keyAAA, keyBBB, bob))

	// Bob exits on a position he was given, having never deposited anything.
	// In v0 this is not expressible at all.
	testing.SetRealm(testing.NewUserRealm(bob))
	gotA, gotB := RemoveLiquidity(cross(cur), keyAAA, keyBBB, 500_000)
	uassert.Equal(t, int64(500_000), gotA)
	uassert.Equal(t, int64(2_000_000), gotB)
	uassert.Equal(t, int64(500_000), tokAAA.BalanceOf(bob), "bob was never funded")
}

// TestLPAllowance: the approve/transferFrom surface v1 gains, and the abort
// when it is spent past its limit.
func TestLPAllowance(cur realm, t *testing.T) {
	reset()
	alice := testutils.TestAddress("allow-alice")
	carol := testutils.TestAddress("allow-carol")
	fund(alice, 10_000_000)

	testing.SetRealm(testing.NewUserRealm(alice))
	AddLiquidity(cross(cur), keyAAA, keyBBB, 1_000_000, 1_000_000)
	ApproveLP(cross(cur), keyAAA, keyBBB, carol, 300_000)
	uassert.Equal(t, int64(300_000), AllowanceLP(keyAAA, keyBBB, alice, carol))

	testing.SetRealm(testing.NewUserRealm(carol))
	TransferFromLP(cross(cur), keyAAA, keyBBB, alice, carol, 300_000)
	uassert.Equal(t, int64(300_000), SharesOf(keyAAA, keyBBB, carol))
	uassert.Equal(t, int64(700_000), SharesOf(keyAAA, keyBBB, alice))
	uassert.Equal(t, int64(0), AllowanceLP(keyAAA, keyBBB, alice, carol))

	uassert.AbortsContains(t, cur, "insufficient allowance", func() {
		TransferFromLP(cross(cur), keyAAA, keyBBB, alice, carol, 1)
	})
}

// TestEachPoolMintsItsOwnLPToken: two pools, two distinct registered tokens.
func TestEachPoolMintsItsOwnLPToken(cur realm, t *testing.T) {
	reset()
	alice := testutils.TestAddress("two-alice")
	fund(alice, 10_000_000)
	ledCCC.Mint(alice, 10_000_000)
	ledCCC.Approve(alice, self(), 10_000_000)

	testing.SetRealm(testing.NewUserRealm(alice))
	AddLiquidity(cross(cur), keyAAA, keyBBB, 1_000_000, 4_000_000)
	AddLiquidity(cross(cur), keyAAA, keyCCC, 2_000_000, 2_000_000)

	ab := LPToken(keyAAA, keyBBB)
	ac := LPToken(keyAAA, keyCCC)
	uassert.NotEqual(t, ab, ac, "one LP token per pool")
	uassert.Equal(t, int64(1_000_000), grc20reg.MustGet(ab).TotalSupply())
	uassert.Equal(t, int64(2_000_000), grc20reg.MustGet(ac).TotalSupply())
	uassert.Equal(t, "AMM LP AAA/CCC", grc20reg.MustGet(ac).GetName())

	// Moving one pool's LP leaves the other alone.
	TransferLP(cross(cur), keyAAA, keyBBB, testutils.TestAddress("two-bob"), 400_000)
	uassert.Equal(t, int64(600_000), SharesOf(keyAAA, keyBBB, alice))
	uassert.Equal(t, int64(2_000_000), SharesOf(keyAAA, keyCCC, alice))
}
