// Realm aaabbb is ONE AMM pair, AAA/BBB, and nothing else.
//
// This is the whole instance half of the instance-per-realm pattern, and it is
// meant to be read in full in one screen: two configuration constants, an init
// that builds the pair and announces it to the registry, and one-line
// re-exports that forward the realm's own `cur` into the shared logic in
// p/moul/x/pair/v0. Every instance in the ecosystem is byte-identical to this
// file except for the two constants, which is what makes verifying an
// unknown instance a two-line diff.
//
// The re-exports cannot be factored away: MsgCall addresses a realm path and a
// function name, so anything a user calls has to be declared here.
//
// State and funds belong to THIS realm: the pair struct is its variable, the
// tokens sit at its own package address, and its creator paid its storage
// deposit. A bug in one instance cannot touch another.
//
// Pattern, and why an AMM is the contested case for it: see the README of
// gno.land/p/moul/x/pair/v0.
package aaabbb

import (
	"gno.land/p/moul/x/pair/v0"
	"gno.land/r/moul/x/pairreg/v0"
	"gno.land/r/nt/grc20reg/v0"

	// Only because both tokens live in this same repository: the blank imports
	// force their init (and therefore their grc20reg registration) to run
	// before this one in a test binary. An instance deployed on chain against
	// already-deployed tokens does not need them.
	_ "gno.land/r/moul/x/pairs/aaa/v0"
	_ "gno.land/r/moul/x/pairs/bbb/v0"
)

// The only two lines that differ between two instances.
const (
	keyA = "gno.land/r/moul/x/pairs/aaa/v0.AAA"
	keyB = "gno.land/r/moul/x/pairs/bbb/v0.BBB"
)

var p *pair.Pair

func init(cur realm) {
	p = pair.New(keyA, keyB, grc20reg.MustGet(keyA), grc20reg.MustGet(keyB))
	pairreg.Register(cross(cur), p)
}

func AddLiquidity(cur realm, maxA, maxB int64) int64 { return p.AddLiquidity(0, cur, maxA, maxB) }

func RemoveLiquidity(cur realm, shares int64) (int64, int64) {
	return p.RemoveLiquidity(0, cur, shares)
}

func Swap(cur realm, keyIn string, amountIn, minOut int64) int64 {
	return p.Swap(0, cur, keyIn, amountIn, minOut)
}

func Quote(keyIn string, amountIn int64) int64 { return p.Quote(keyIn, amountIn) }
func Reserves() (int64, int64)                 { return p.Reserves() }
func SharesOf(owner address) int64             { return p.SharesOf(owner) }
func TotalShares() int64                       { return p.TotalShares() }
func Keys() (string, string)                   { return p.Keys() }
func Render(path string) string                { return p.Render(path) }
