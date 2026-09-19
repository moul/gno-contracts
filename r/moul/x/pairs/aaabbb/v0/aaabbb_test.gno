package aaabbb

import (
	"chain"
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/r/moul/x/pairreg/v0"
	"gno.land/r/moul/x/pairs/aaa/v0"
	"gno.land/r/moul/x/pairs/bbb/v0"
)

const selfPath = "gno.land/r/moul/x/pairs/aaabbb/v0"

func self() address { return chain.PackageAddress(selfPath) }

// fund gives addr both tokens and approves this instance to spend them.
func fund(cur realm, addr address) {
	testing.SetRealm(testing.NewUserRealm(addr))
	aaa.Faucet(cross(cur))
	bbb.Faucet(cross(cur))
	aaa.Approve(cross(cur), self(), 1_000_000_000)
	bbb.Approve(cross(cur), self(), 1_000_000_000)
}

// Deploying the instance is the whole "factory call": its init builds the pair
// and announces it, so one addpkg both creates and lists it.
func TestSelfRegisteredAtInit(t *testing.T) {
	e := pairreg.Get(selfPath)
	uassert.True(t, e != nil, "instance must register itself in init")
	uassert.Equal(t, selfPath, e.Path)
	uassert.Equal(t, 1, pairreg.Size())

	keyA, keyB := Keys()
	uassert.Equal(t, "gno.land/r/moul/x/pairs/aaa/v0.AAA", keyA)
	uassert.Equal(t, "gno.land/r/moul/x/pairs/bbb/v0.BBB", keyB)
}

// The registry holds a live pointer into this realm's storage, so its own
// Render shows state it never copied. This is the property that lets one
// qrender describe a thousand instances.
func TestRegistrySeesLiveState(cur realm, t *testing.T) {
	alice := testutils.TestAddress("alice-live")
	fund(cur, alice)
	AddLiquidity(cross(cur), 1_000_000, 4_000_000)

	e := pairreg.Get(selfPath)
	resA, resB := e.Pair.Reserves()
	uassert.Equal(t, int64(1_000_000), resA)
	uassert.Equal(t, int64(4_000_000), resB)

	index := pairreg.Render("")
	uassert.True(t, strings.Contains(index, "AAA/BBB"), "index lists the couple")
	uassert.True(t, strings.Contains(index, "1000000 AAA"), "index shows live reserves")
	uassert.True(t, strings.Contains(index, "moul/x/pairs/aaabbb/v0"), "index links the instance")

	// Wind the pair back down so the next test starts from an empty pool.
	RemoveLiquidity(cross(cur), TotalShares())
}

// Full lifecycle through the instance's own entry points, which is also the
// proof that funds move to and from THIS realm's address while every line of
// logic runs in the shared pure package.
func TestLifecycle(cur realm, t *testing.T) {
	alice := testutils.TestAddress("alice-cycle")
	fund(cur, alice)

	minted := AddLiquidity(cross(cur), 1_000_000, 4_000_000)
	uassert.Equal(t, int64(1_000_000), minted, "first deposit mints amountA, no sqrt")
	uassert.Equal(t, int64(1_000_000), aaa.BalanceOf(self()), "tokens land on the instance")
	uassert.Equal(t, int64(4_000_000), bbb.BalanceOf(self()))
	uassert.Equal(t, minted, SharesOf(alice))

	quoted := Quote("gno.land/r/moul/x/pairs/aaa/v0.AAA", 100_000)
	out := Swap(cross(cur), "gno.land/r/moul/x/pairs/aaa/v0.AAA", 100_000, 362_000)
	uassert.Equal(t, int64(362_644), out, "same pricing as the single-realm design")
	uassert.Equal(t, quoted, out, "Quote matches what Swap pays")

	resA, resB := Reserves()
	uassert.Equal(t, int64(1_100_000), resA)
	uassert.Equal(t, int64(3_637_356), resB)

	gotA, gotB := RemoveLiquidity(cross(cur), 500_000)
	uassert.Equal(t, int64(550_000), gotA)
	uassert.Equal(t, int64(1_818_678), gotB)

	// The last provider out is paid the whole reserve, so nothing is stranded.
	gotA, gotB = RemoveLiquidity(cross(cur), TotalShares())
	uassert.Equal(t, int64(550_000), gotA)
	uassert.Equal(t, int64(1_818_678), gotB)
	uassert.Equal(t, int64(0), TotalShares())
	uassert.Equal(t, int64(0), aaa.BalanceOf(self()), "instance holds nothing afterwards")
	uassert.Equal(t, int64(0), bbb.BalanceOf(self()))
}

// A token this pair does not hold must be refused by name, not silently
// treated as one of the two sides. Asserted through Quote, which reaches the
// same guard without a crossing call: a panic raised inside a crossing call
// unwinds the whole transaction and is not recoverable by the caller.
func TestRejectsForeignToken(cur realm, t *testing.T) {
	alice := testutils.TestAddress("alice-foreign")
	fund(cur, alice)
	AddLiquidity(cross(cur), 1_000_000, 4_000_000)

	uassert.PanicsWithMessage(t, cur, "pair: gno.land/r/nope/v0.NOPE is not in this pair", func() {
		Quote("gno.land/r/nope/v0.NOPE", 1_000)
	})
	RemoveLiquidity(cross(cur), TotalShares())
}

func TestRender(cur realm, t *testing.T) {
	alice := testutils.TestAddress("alice-render")
	fund(cur, alice)

	empty := Render("")
	uassert.True(t, strings.Contains(empty, "# AAA / BBB"))
	uassert.True(t, strings.Contains(empty, "Empty"), "empty pair says so")

	AddLiquidity(cross(cur), 1_000_000, 4_000_000)
	full := Render("")
	uassert.True(t, strings.Contains(full, "| AAA | 1000000 |"), "reserves row")
	uassert.True(t, strings.Contains(full, "LP shares: **1000000**"))
	uassert.True(t, strings.Contains(full, "1 AAA buys ~4 BBB"), "spot line")
	RemoveLiquidity(cross(cur), TotalShares())
}
