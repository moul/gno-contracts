// Package grc20faucet issues two free GRC20 tokens, RED and BLUE, and gives
// them away on request.
//
// It exists so that anything needing a token to experiment on has one that is
// worthless, unlimited and shared. Both tokens are registered in
// gno.land/r/nt/grc20reg/v0, which is what lets another realm find and move
// them by key without importing this package: that indirection is the whole
// point, and it is what gno.land/r/moul/x/grc20wrapdemo/v0 wraps.
//
// Two tokens rather than one, because the interesting patterns start at two: a
// meta-token over a pair needs a pair.
package grc20faucet

import (
	"chain/runtime"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/grc20/v0"
	"gno.land/p/nt/ufmt/v0"
	"gno.land/r/nt/grc20reg/v0"
)

// Tokens are exported so an importing realm can read them directly; the
// ledgers stay private, since they carry unrestricted mint and burn.
var (
	Red  *grc20.Token
	Blue *grc20.Token

	redLedger  *grc20.PrivateLedger
	blueLedger *grc20.PrivateLedger

	// RedKey and BlueKey are the grc20reg lookup keys, the way a realm that
	// does NOT import this package refers to these tokens.
	RedKey  string
	BlueKey string

	lastClaim = avl.NewTree() // address -> block height of its last claim
)

const (
	decimals = 4

	// ClaimAmount is minted of EACH token per claim: 100.0000 units.
	ClaimAmount = int64(1_000_000)

	// ClaimEvery is the cooldown, in blocks, between two claims by the same
	// account. Free money with no cooldown is a spam vector, not a faucet.
	ClaimEvery = int64(100)
)

func init(cur realm) {
	Red, redLedger = grc20.NewToken("Red Token", "RED", decimals, 0, cur)
	Blue, blueLedger = grc20.NewToken("Blue Token", "BLUE", decimals, 1, cur)
	RedKey = grc20reg.Register(cross(cur), Red, "red")
	BlueKey = grc20reg.Register(cross(cur), Blue, "blue")
}

// Claim mints ClaimAmount of both RED and BLUE to the caller.
func Claim(cur realm) {
	who := caller(cur)
	now := runtime.ChainHeight()
	if next, ok := NextClaim(who); ok && now < next {
		panic(ufmt.Sprintf("too soon: next claim at block %d, current %d", next, now))
	}
	lastClaim.Set(who.String(), now)
	checkErr(redLedger.Mint(who, ClaimAmount))
	checkErr(blueLedger.Mint(who, ClaimAmount))
}

// NextClaim returns the block height at which `who` may claim again, and
// whether they have ever claimed at all.
func NextClaim(who address) (int64, bool) {
	v := lastClaim.Get(who.String())
	if v == nil {
		return 0, false
	}
	return v.(int64) + ClaimEvery, true
}

// Transfer moves the caller's own units of `symbol`.
func Transfer(cur realm, symbol string, to address, amount int64) {
	checkErr(ledgerOf(symbol).CallerTeller().Transfer(0, cur, to, amount))
}

// Approve lets `spender` draw `amount` of `symbol` from the caller's balance.
//
// This is the call that makes every wrapper in grc20wrapdemo work: the wrapper
// realm has no authority over anybody's tokens until its address is named here.
func Approve(cur realm, symbol string, spender address, amount int64) {
	checkErr(ledgerOf(symbol).CallerTeller().Approve(0, cur, spender, amount))
}

// TransferFrom spends an allowance the caller was granted.
func TransferFrom(cur realm, symbol string, from, to address, amount int64) {
	checkErr(ledgerOf(symbol).CallerTeller().TransferFrom(0, cur, from, to, amount))
}

// BalanceOf returns `owner`'s balance of `symbol`.
func BalanceOf(symbol string, owner address) int64 {
	return tokenOf(symbol).BalanceOf(owner)
}

// Allowance returns what `owner` let `spender` draw of `symbol`.
func Allowance(symbol string, owner, spender address) int64 {
	return tokenOf(symbol).Allowance(owner, spender)
}

// TotalSupply returns how much of `symbol` has been claimed so far.
func TotalSupply(symbol string) int64 {
	return tokenOf(symbol).TotalSupply()
}

func tokenOf(symbol string) *grc20.Token {
	switch symbol {
	case "RED":
		return Red
	case "BLUE":
		return Blue
	}
	panic("unknown symbol " + symbol + " (RED or BLUE)")
}

func ledgerOf(symbol string) *grc20.PrivateLedger {
	switch symbol {
	case "RED":
		return redLedger
	case "BLUE":
		return blueLedger
	}
	panic("unknown symbol " + symbol + " (RED or BLUE)")
}

// caller is the account or realm that crossed into this one.
func caller(cur realm) address {
	if !cur.IsCurrent() {
		panic("grc20faucet: stale realm token")
	}
	return cur.Previous().Address()
}

func checkErr(err error) {
	if err != nil {
		panic(err)
	}
}

func Render(path string) string {
	s := "# GRC20 faucet: RED and BLUE\n\n"
	s += "Two worthless tokens to experiment on. `Claim` gives you "
	s += ufmt.Sprintf("%d of each, once every %d blocks.\n\n", ClaimAmount, ClaimEvery)

	s += "| token | symbol | decimals | supply | registry key |\n"
	s += "|---|---|---|---|---|\n"
	s += ufmt.Sprintf("| %s | RED | %d | %d | `%s` |\n",
		Red.GetName(), Red.GetDecimals(), Red.TotalSupply(), RedKey)
	s += ufmt.Sprintf("| %s | BLUE | %d | %d | `%s` |\n",
		Blue.GetName(), Blue.GetDecimals(), Blue.TotalSupply(), BlueKey)

	s += "\n## Use it\n\n"
	s += "```\n"
	s += "gnokey maketx call -pkgpath gno.land/r/moul/x/grc20faucet/v0 -func Claim ...\n"
	s += "gnokey maketx call -pkgpath gno.land/r/moul/x/grc20faucet/v0 -func Approve \\\n"
	s += "  -args RED -args <spender> -args 1000000 ...\n"
	s += "```\n\n"
	s += "Both tokens are registered in [grc20reg](/r/nt/grc20reg/v0), so a realm can\n"
	s += "move them by key without importing this one. That is what\n"
	s += "[grc20wrapdemo](/r/moul/x/grc20wrapdemo/v0) does with them.\n"

	if path != "" {
		s += "\n---\n\n"
		s += ufmt.Sprintf("Balance of `%s`: RED %d, BLUE %d\n",
			path, Red.BalanceOf(address(path)), Blue.BalanceOf(address(path)))
	}
	return s
}
