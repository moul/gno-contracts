package amm

import (
	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/testutils/v0"
)

// seedExamplePool installs one deterministic pool so the examples below do not
// depend on which tests ran before them. The numbers are the worked example
// from the package docs: a 1,000,000 / 4,000,000 pool after a 100,000 swap.
func seedExamplePool() {
	pools = avl.Tree{}
	p := &pool{
		keyA: keyAAA, keyB: keyBBB,
		tokA: tokAAA, tokB: tokBBB,
		resA: 1_100_000, resB: 3_637_356,
		totalShares: 1_000_000,
		shares:      avl.NewTree(),
	}
	p.shares.Set(testutils.TestAddress("lp").String(), int64(1_000_000))
	pools.Set(poolID(keyAAA, keyBBB), p)
}

// ExampleRender pins the realm's home page.
func ExampleRender() {
	seedExamplePool()
	print(Render(""))
	// Output:
	// # Minimal AMM
	//
	// Constant product (`x*y=k`) with a 30 bps fee kept by the pool. Reserves are stored, never read from balances, so sending tokens here directly does nothing and they cannot be recovered.
	//
	// | pool | reserves | LP shares | providers |
	// |---|---|---|---|
	// | [AAA/BBB](/r/moul/x/amm/v0:gno.land/r/moul/x/amm/v0.AAA~gno.land/r/moul/x/amm/v0.BBB) | 1100000 AAA / 3637356 BBB | 1000000 | 1 |
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
	// - **LP shares**: 1000000 across 1 provider(s)
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
