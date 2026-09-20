// Package aaa is a throwaway GRC20 with an open faucet, used to exercise the
// pair instances in this repo. It has no value and no owner controls.
package aaa

import (
	"gno.land/p/nt/grc20/v0"
	"gno.land/r/nt/grc20reg/v0"
)

var (
	Token         *grc20.Token
	privateLedger *grc20.PrivateLedger
	userTeller    grc20.Teller
)

// Key is this token's grc20reg key, the string an instance realm is
// configured with.
const Key = "gno.land/r/moul/x/pairs/aaa/v0.AAA"

func init(cur realm) {
	Token, privateLedger = grc20.NewToken("Test Alpha", "AAA", 6, 0, cur)
	userTeller = privateLedger.CallerTeller()
	grc20reg.Register(cross(cur), Token, "")
}

// Faucet mints a fixed amount to the caller. Unrestricted on purpose.
func Faucet(cur realm) {
	if err := privateLedger.Mint(cur.Previous().Address(), 1_000_000_000); err != nil {
		panic(err)
	}
}

func TotalSupply() int64                      { return userTeller.TotalSupply() }
func BalanceOf(owner address) int64           { return userTeller.BalanceOf(owner) }
func Allowance(owner, spender address) int64  { return userTeller.Allowance(owner, spender) }

func Transfer(cur realm, to address, amount int64) {
	if err := userTeller.Transfer(0, cur, to, amount); err != nil {
		panic(err)
	}
}

func Approve(cur realm, spender address, amount int64) {
	if err := userTeller.Approve(0, cur, spender, amount); err != nil {
		panic(err)
	}
}

func Render(string) string {
	return "# AAA\n\nThrowaway test token for the pair instances. `Faucet` mints 1000 AAA to you.\n"
}
