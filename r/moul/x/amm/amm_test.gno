package amm

import (
	"chain"
	"testing"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/grc20/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/r/nt/grc20reg/v0"
)

// Two throwaway tokens, minted and registered once for the whole test binary.
// They are created from this realm, so grc20reg keys them under this path.
var (
	tokAAA, tokBBB *grc20.Token
	ledAAA, ledBBB *grc20.PrivateLedger
	keyAAA, keyBBB string
)

func init(cur realm) {
	tokAAA, ledAAA = grc20.NewToken("Test Alpha", "AAA", 6, 0, cur)
	tokBBB, ledBBB = grc20.NewToken("Test Beta", "BBB", 6, 1, cur)
	keyAAA = grc20reg.Register(cross(cur), tokAAA, "")
	keyBBB = grc20reg.Register(cross(cur), tokBBB, "")
}

func self() address { return chain.PackageAddress("gno.land/r/moul/x/amm/v0") }

// fund mints both tokens to addr and approves this realm to spend them.
func fund(addr address, amount int64) {
	ledAAA.Mint(addr, amount)
	ledBBB.Mint(addr, amount)
	ledAAA.Approve(addr, self(), amount)
	ledBBB.Approve(addr, self(), amount)
}

// reset clears every pool so each test starts from an empty realm.
func reset() { pools = avl.Tree{} }

//
// Pure arithmetic.
//

func TestAmountOut(t *testing.T) {
	cases := []struct {
		name                   string
		in, resIn, resOut, want int64
	}{
		{"balanced pool, small trade", 1_000, 1_000_000, 1_000_000, 996},
		{"balanced pool, 1%", 10_000, 1_000_000, 1_000_000, 9_871},
		{"balanced pool, 10%", 100_000, 1_000_000, 1_000_000, 90_661},
		{"balanced pool, 50%", 500_000, 1_000_000, 1_000_000, 332_665},
		{"skewed pool", 100_000, 1_000_000, 4_000_000, 362_644},
		{"near drain", 1_000, 1, 1_000_000, 998_997},
		{"dust rounds to zero", 1, 1_000_000, 1_000_000, 0},
		{"reserves at the cap", maxReserve / 2, maxReserve / 2, maxReserve, 4_604_758_097_518_382},
	}
	for _, tc := range cases {
		got := AmountOut(tc.in, tc.resIn, tc.resOut)
		uassert.Equal(t, tc.want, got, tc.name)
	}
}

func TestAmountOutNeverBreaksK(t *testing.T) {
	resIn, resOut := int64(3_000_000), int64(7_500_000)
	for _, in := range []int64{1, 7, 1_000, 999_999, 3_000_000} {
		out := AmountOut(in, resIn, resOut)
		uassert.True(t, out < resOut, "output must stay inside the reserve")
		uassert.True(t, cmpProd(resIn+in, resOut-out, resIn, resOut) >= 0, "k must not decrease")
	}
}

func TestAmountOutGuards(cur realm, t *testing.T) {
	uassert.PanicsWithMessage(t, cur, "amm: amountIn must be > 0", func() {
		AmountOut(0, 1_000, 1_000)
	})
	uassert.PanicsWithMessage(t, cur, "amm: pool has an empty reserve", func() {
		AmountOut(1, 0, 1_000)
	})
	uassert.PanicsWithMessage(t, cur, "amm: reserve above cap", func() {
		AmountOut(1, maxReserve+1, 1_000)
	})
	uassert.PanicsWithMessage(t, cur, "amm: reserve cap exceeded", func() {
		AmountOut(maxReserve, maxReserve, 1_000)
	})
}

func TestMulDiv(t *testing.T) {
	uassert.Equal(t, int64(0), mulDiv(0, 12345, 7))
	uassert.Equal(t, int64(3), mulDiv(7, 5, 10)) // floors
	// 2^62 * 4 is 2^64: the intermediate does not fit in int64, the result does.
	const big = int64(1) << 62
	uassert.Equal(t, big/2, mulDiv(big, 4, 8))
	// maxReserve * feeDen is the widest product this realm ever forms.
	uassert.Equal(t, int64(maxReserve), mulDiv(maxReserve, feeDen, feeDen))
}

func TestCmpProd(t *testing.T) {
	const big = int64(1) << 40
	uassert.Equal(t, 0, cmpProd(big, big, big, big))
	uassert.Equal(t, -1, cmpProd(big, big, big, big+1))
	uassert.Equal(t, 1, cmpProd(big, big+1, big, big))
}

//
// Lifecycle.
//

func TestSeedSwapRemove(cur realm, t *testing.T) {
	reset()
	alice := testutils.TestAddress("seed-alice")
	fund(alice, 10_000_000)

	testing.SetRealm(testing.NewUserRealm(alice))
	heldA, heldB := tokAAA.BalanceOf(self()), tokBBB.BalanceOf(self())

	// Seed: the first provider sets the price and gets shares == amountA.
	minted := AddLiquidity(cross(cur), keyAAA, keyBBB, 1_000_000, 4_000_000)
	uassert.Equal(t, int64(1_000_000), minted)
	uassert.Equal(t, int64(1), int64(PoolCount()))

	rA, rB := Reserves(keyAAA, keyBBB)
	uassert.Equal(t, int64(1_000_000), rA)
	uassert.Equal(t, int64(4_000_000), rB)
	uassert.Equal(t, heldA+1_000_000, tokAAA.BalanceOf(self()), "reserve is really held")

	// Swap AAA -> BBB.
	quoted := Quote(keyAAA, keyBBB, 100_000)
	uassert.Equal(t, int64(362_644), quoted)
	out := Swap(cross(cur), keyAAA, keyBBB, 100_000, 362_000)
	uassert.Equal(t, quoted, out)

	rA, rB = Reserves(keyAAA, keyBBB)
	uassert.Equal(t, int64(1_100_000), rA)
	uassert.Equal(t, int64(3_637_356), rB)
	uassert.True(t, cmpProd(rA, rB, 1_000_000, 4_000_000) > 0, "fee grew k")

	// Burn half the position.
	gotA, gotB := RemoveLiquidity(cross(cur), keyAAA, keyBBB, 500_000)
	uassert.Equal(t, int64(550_000), gotA)
	uassert.Equal(t, int64(1_818_678), gotB)
	uassert.Equal(t, int64(500_000), TotalShares(keyAAA, keyBBB))

	// Burn the rest: the last provider out takes the whole reserve.
	gotA, gotB = RemoveLiquidity(cross(cur), keyAAA, keyBBB, 500_000)
	uassert.Equal(t, int64(550_000), gotA)
	uassert.Equal(t, int64(1_818_678), gotB)
	uassert.Equal(t, int64(0), TotalShares(keyAAA, keyBBB))
	rA, rB = Reserves(keyAAA, keyBBB)
	uassert.Equal(t, int64(0), rA)
	uassert.Equal(t, int64(0), rB)
	uassert.Equal(t, heldA, tokAAA.BalanceOf(self()), "nothing unclaimable left behind")
	uassert.Equal(t, heldB, tokBBB.BalanceOf(self()), "nothing unclaimable left behind")

	// A drained pool is reseedable, at whatever price the next provider picks.
	uassert.Equal(t, int64(200_000), AddLiquidity(cross(cur), keyAAA, keyBBB, 200_000, 100_000))
	rA, rB = Reserves(keyAAA, keyBBB)
	uassert.Equal(t, int64(200_000), rA)
	uassert.Equal(t, int64(100_000), rB)
}

func TestArgumentOrderIsSymmetric(cur realm, t *testing.T) {
	reset()
	alice := testutils.TestAddress("sym-alice")
	fund(alice, 10_000_000)
	testing.SetRealm(testing.NewUserRealm(alice))

	AddLiquidity(cross(cur), keyBBB, keyAAA, 4_000_000, 1_000_000)
	uassert.Equal(t, int64(1), int64(PoolCount()), "one pool whichever order is used")

	rA, rB := Reserves(keyAAA, keyBBB)
	uassert.Equal(t, int64(1_000_000), rA)
	uassert.Equal(t, int64(4_000_000), rB)

	rB2, rA2 := Reserves(keyBBB, keyAAA)
	uassert.Equal(t, rA, rA2, "reserves follow the caller's order")
	uassert.Equal(t, rB, rB2, "reserves follow the caller's order")
}

func TestSecondProviderIsTrimmedToRatio(cur realm, t *testing.T) {
	reset()
	alice := testutils.TestAddress("trim-alice")
	bob := testutils.TestAddress("trim-bob")
	fund(alice, 10_000_000)
	fund(bob, 10_000_000)

	testing.SetRealm(testing.NewUserRealm(alice))
	AddLiquidity(cross(cur), keyAAA, keyBBB, 1_000_000, 4_000_000)

	// Bob offers a badly skewed pair: 100k AAA is only worth 400k BBB, so the
	// extra BBB is left in his wallet and his shares price off the scarce side.
	testing.SetRealm(testing.NewUserRealm(bob))
	beforeB := tokBBB.BalanceOf(bob)
	minted := AddLiquidity(cross(cur), keyAAA, keyBBB, 100_000, 9_000_000)
	uassert.Equal(t, int64(100_000), minted)
	uassert.Equal(t, int64(400_000), beforeB-tokBBB.BalanceOf(bob), "only the ratio amount was taken")

	rA, rB := Reserves(keyAAA, keyBBB)
	uassert.Equal(t, int64(1_100_000), rA)
	uassert.Equal(t, int64(4_400_000), rB)
	uassert.Equal(t, int64(1_100_000), TotalShares(keyAAA, keyBBB))

	// Round-trip: Bob can never take out more than he put in.
	gotA, gotB := RemoveLiquidity(cross(cur), keyAAA, keyBBB, minted)
	uassert.True(t, gotA <= 100_000, "no value created on the A side")
	uassert.True(t, gotB <= 400_000, "no value created on the B side")
}

func TestDonationIsInert(cur realm, t *testing.T) {
	reset()
	alice := testutils.TestAddress("don-alice")
	mallory := testutils.TestAddress("don-mallory")
	fund(alice, 10_000_000)
	fund(mallory, 10_000_000)

	testing.SetRealm(testing.NewUserRealm(alice))
	AddLiquidity(cross(cur), keyAAA, keyBBB, 1_000_000, 1_000_000)
	before := Quote(keyAAA, keyBBB, 10_000)

	// Mallory sends 5,000,000 AAA straight to the realm address, the classic
	// setup for a share-inflation or price-manipulation attack.
	heldA := tokAAA.BalanceOf(self())
	ledAAA.Transfer(mallory, self(), 5_000_000)
	uassert.Equal(t, heldA+5_000_000, tokAAA.BalanceOf(self()), "the balance really moved")

	rA, rB := Reserves(keyAAA, keyBBB)
	uassert.Equal(t, int64(1_000_000), rA, "reserves ignore balances")
	uassert.Equal(t, int64(1_000_000), rB, "reserves ignore balances")
	uassert.Equal(t, before, Quote(keyAAA, keyBBB, 10_000), "price is unchanged")

	// And a later provider is priced off reserves, not off the donation.
	testing.SetRealm(testing.NewUserRealm(mallory))
	uassert.Equal(t, int64(1_000_000), AddLiquidity(cross(cur), keyAAA, keyBBB, 1_000_000, 1_000_000))
}

//
// Guards.
//

func TestGuards(cur realm, t *testing.T) {
	reset()
	alice := testutils.TestAddress("guard-alice")
	fund(alice, 10_000_000)
	testing.SetRealm(testing.NewUserRealm(alice))

	uassert.AbortsWithMessage(t, cur, "amm: a pool needs two different tokens", func() {
		AddLiquidity(cross(cur), keyAAA, keyAAA, 1, 1)
	})
	uassert.AbortsWithMessage(t, cur, "amm: both deposit amounts must be > 0", func() {
		AddLiquidity(cross(cur), keyAAA, keyBBB, 0, 1)
	})
	uassert.AbortsWithMessage(t, cur, "amm: no such pool: "+keyAAA+"~"+keyBBB, func() {
		Swap(cross(cur), keyAAA, keyBBB, 1, 0)
	})

	AddLiquidity(cross(cur), keyAAA, keyBBB, 1_000_000, 1_000_000)

	uassert.AbortsWithMessage(t, cur, "amm: slippage, output below minOut", func() {
		Swap(cross(cur), keyAAA, keyBBB, 10_000, 10_000)
	})
	uassert.AbortsWithMessage(t, cur, "amm: output rounds to zero", func() {
		Swap(cross(cur), keyAAA, keyBBB, 1, 0)
	})
	uassert.AbortsWithMessage(t, cur, "amm: amountIn must be > 0", func() {
		Swap(cross(cur), keyAAA, keyBBB, 0, 0)
	})
	uassert.AbortsWithMessage(t, cur, "amm: insufficient shares", func() {
		RemoveLiquidity(cross(cur), keyAAA, keyBBB, 2_000_000)
	})
	uassert.AbortsWithMessage(t, cur, "amm: reserve cap exceeded", func() {
		AddLiquidity(cross(cur), keyAAA, keyBBB, maxReserve, maxReserve)
	})

	// An allowance that does not cover the deposit aborts, and nothing moved.
	bob := testutils.TestAddress("guard-bob")
	ledAAA.Mint(bob, 1_000_000)
	ledBBB.Mint(bob, 1_000_000)
	ledAAA.Approve(bob, self(), 10)
	ledBBB.Approve(bob, self(), 1_000_000)
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "insufficient allowance", func() {
		AddLiquidity(cross(cur), keyAAA, keyBBB, 100_000, 100_000)
	})
	uassert.Equal(t, int64(1_000_000), tokAAA.BalanceOf(bob), "nothing moved: the first pull failed")
	uassert.Equal(t, int64(0), SharesOf(keyAAA, keyBBB, bob))
}
