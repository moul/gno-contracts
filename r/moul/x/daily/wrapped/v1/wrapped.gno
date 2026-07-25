// Package wrapped is an accounting-only port of Wrapped Ether (WETH).
//
// The canonical WETH contract lets anyone lock native ETH and mint a 1:1
// ERC-20 representation (and burn it back). On gno.land / topaz there is no
// msg.value / payable, so there is NO real coin transfer here: Deposit and
// Withdraw are pure accounting operations that model the wrap/unwrap. Balances
// and totalSupply are plain uint64 ledgers kept in an avl.Tree.
package wrapped

import (
	"strconv"

	"chain"
	"chain/runtime/unsafe"

	"gno.land/p/nt/avl/v0"
)

// balances maps owner address (string) -> wrapped balance (uint64).
var (
	balances    avl.Tree
	totalSupply uint64
)

// Deposit wraps `amount` units of the (notional) native coin, crediting the
// caller's wrapped balance and the global totalSupply. Accounting only: no real
// coin ever moves — it models locking native funds to mint the wrapped token.
func Deposit(cur realm, amount uint64) {
	if amount == 0 {
		panic("wrapped: deposit amount must be > 0")
	}
	owner := unsafe.PreviousRealm().Address()
	setBalance(owner, balanceOf(owner)+amount)
	totalSupply += amount
	chain.Emit("Deposit", "dst", owner.String(), "wad", strconv.FormatUint(amount, 10))
}

// Withdraw unwraps `amount` units, burning them from the caller's balance and
// from totalSupply. Panics if the caller lacks the balance.
func Withdraw(cur realm, amount uint64) {
	if amount == 0 {
		panic("wrapped: withdraw amount must be > 0")
	}
	owner := unsafe.PreviousRealm().Address()
	bal := balanceOf(owner)
	if bal < amount {
		panic("wrapped: insufficient balance")
	}
	setBalance(owner, bal-amount)
	totalSupply -= amount
	chain.Emit("Withdrawal", "src", owner.String(), "wad", strconv.FormatUint(amount, 10))
}

// Transfer moves `amount` wrapped units from the caller to `to`.
func Transfer(cur realm, to address, amount uint64) {
	if amount == 0 {
		panic("wrapped: transfer amount must be > 0")
	}
	from := unsafe.PreviousRealm().Address()
	if from == to {
		panic("wrapped: cannot transfer to self")
	}
	fromBal := balanceOf(from)
	if fromBal < amount {
		panic("wrapped: insufficient balance")
	}
	setBalance(from, fromBal-amount)
	setBalance(to, balanceOf(to)+amount)
	chain.Emit("Transfer", "src", from.String(), "dst", to.String(), "wad", strconv.FormatUint(amount, 10))
}

// balanceOf returns the wrapped balance of `owner` (read-only, not crossing).
func balanceOf(owner address) uint64 {
	v := balances.Get(owner.String())
	if v == nil {
		return 0
	}
	return v.(uint64)
}

// BalanceOf is the exported read-only accessor for a single owner.
func BalanceOf(owner address) uint64 { return balanceOf(owner) }

// TotalSupply returns the total amount of wrapped units in existence.
func TotalSupply() uint64 { return totalSupply }

func setBalance(owner address, amount uint64) {
	if amount == 0 {
		balances.Remove(owner.String())
		return
	}
	balances.Set(owner.String(), amount)
}

// ---- pure/read-only helpers (unit-tested) ----

// canDebit reports whether `bal` can cover `amount` for a burn/transfer.
func canDebit(bal, amount uint64) bool {
	return amount > 0 && bal >= amount
}

// formatUnits renders a raw uint64 amount as a decimal string.
func formatUnits(n uint64) string {
	return strconv.FormatUint(n, 10)
}

// Render shows the total supply and a table of non-zero balances.
func Render(path string) string {
	out := "# Wrapped (WETH-style, accounting-only)\n\n"
	out += "Deposit mints wrapped units, Withdraw burns them. No real coins move — this is a pure ledger.\n\n"
	out += "**Total supply:** " + formatUnits(totalSupply) + "\n\n"

	if balances.Size() == 0 {
		out += "_No balances yet. Call `Deposit` to wrap some units._\n"
		return out
	}

	out += "| Owner | Balance |\n|---|---:|\n"
	balances.Iterate("", "", func(key string, value interface{}) bool {
		out += "| `" + key + "` | " + formatUnits(value.(uint64)) + " |\n"
		return false
	})
	return out
}
