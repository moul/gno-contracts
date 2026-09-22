package amm

import (
	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/grc20/v0"
	"gno.land/p/nt/testutils/v0"
)

// A fixed LP token for the examples, so the rendered symbol does not depend on
// how many pools the other tests happened to open first.
var (
	exLP    *grc20.Token
	exLedge *grc20.PrivateLedger
)

func init(cur realm) {
	exLP, exLedge = grc20.NewToken("AMM LP AAA/BBB", "LPDEMO", 6, 9999, cur)
	exLedge.Mint(testutils.TestAddress("lp"), 1_000_000)
}

// seedExamplePool installs one deterministic pool so the examples below do not
// depend on which tests ran before them. The numbers are the worked example
// from the package docs: a 1,000,000 / 4,000,000 pool after a 100,000 swap.
func seedExamplePool() {
	pools = avl.Tree{}
	pools.Set(poolID(keyAAA, keyBBB), &pool{
		keyA: keyAAA, keyB: keyBBB,
		tokA: tokAAA, tokB: tokBBB,
		resA: 1_100_000, resB: 3_637_356,
		lp: exLP, lpLedger: exLedge,
		lpKey: "gno.land/r/moul/x/amm/v0.LPDEMO",
	})
}

// ExampleRender pins the realm's home page.
func ExampleRender() {
	seedExamplePool()
	print(Render(""))
	// Output:
	// # Minimal AMM
	//
	// Constant product (`x*y=k`) with a 30 bps fee kept by the pool. Every position is a transferable GRC20 LP token. Reserves are stored, never read from balances, so sending tokens here directly does nothing and they cannot be recovered.
	//
	// | pool | reserves | LP token | supply | holders |
	// |---|---|---|---|---|
	// | [AAA/BBB](/r/moul/x/amm/v0:gno.land/r/moul/x/amm/v0.AAA~gno.land/r/moul/x/amm/v0.BBB) | 1100000 AAA / 3637356 BBB | LPDEMO | 1000000 | 1 |
}

// ExampleRender_pool pins a single pool's detail page.
func ExampleRender_pool() {
	seedExamplePool()
	print(Render(poolID(keyAAA, keyBBB)))
	// Output:
	// # AAA / BBB
	//
	// - **AAA** reserve: 1100000 (`gno.land/r/moul/x/amm/v0.AAA`)
	// - **BBB** reserve: 3637356 (`gno.land/r/moul/x/amm/v0.BBB`)
	// - **LP token**: `gno.land/r/moul/x/amm/v0.LPDEMO` (LPDEMO)
	// - **LP shares**: 1000000 across 1 holder(s)
}

// ExampleRender_unknown pins the miss.
func ExampleRender_unknown() {
	seedExamplePool()
	print(Render("nope"))
	// Output:
	// # 404
	//
	// No pool `nope`.
}
