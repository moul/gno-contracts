// Package erc20 implements MiniToken, a minimal fungible token modeled on the
// Solidity ERC-20 idea, ported to gno.land (gno 0.9 / test13).
//
// State is package-level and persistent. All state-mutating exported functions
// are crossing functions (they take `cur realm` as the first parameter) per the
// gno 0.9 interrealm convention, and identify the caller via
// cur.Previous().Address() after checking cur.IsCurrent().
package erc20

import (
	"errors"
	"sort"
	"strconv"
	"strings"
)

const (
	name   = "MiniToken"
	symbol = "MINI"
)

var (
	// balances maps holder address -> token balance.
	balances = map[address]uint64{}
	// allowances[owner][spender] = amount the spender may pull from owner.
	allowances = map[address]map[address]uint64{}
	// totalSupply is the sum of all balances.
	totalSupply uint64
)

var (
	errZeroAddress  = errors.New("erc20: zero address")
	errInsufficient = errors.New("erc20: insufficient balance")
	errAllowanceLow = errors.New("erc20: insufficient allowance")
	errOverflow     = errors.New("erc20: supply overflow")
	errSpoofedRealm = errors.New("erc20: spoofed realm")
	errNotUser      = errors.New("erc20: caller is not a user account")
)

// caller returns the immediate caller's address for a crossing function.
// It enforces the gno 0.9 authentication primitive: cur must be the live
// crossing frame before its Previous() is trusted.
func caller(cur realm) address {
	if !cur.IsCurrent() {
		panic(errSpoofedRealm)
	}
	prev := cur.Previous()
	if !prev.IsUser() {
		panic(errNotUser)
	}
	return prev.Address()
}

// Mint creates `amount` new tokens and credits them to `to`, increasing the
// total supply. Crossing function.
func Mint(cur realm, to address, amount uint64) {
	_ = caller(cur) // authenticate the crossing frame; anyone may mint in this demo
	if !to.IsValid() {
		panic(errZeroAddress)
	}
	if amount == 0 {
		return
	}
	if totalSupply+amount < totalSupply {
		panic(errOverflow)
	}
	totalSupply += amount
	balances[to] += amount
}

// Transfer moves `amount` tokens from the caller to `to`. Crossing function.
func Transfer(cur realm, to address, amount uint64) {
	from := caller(cur)
	if !to.IsValid() {
		panic(errZeroAddress)
	}
	if err := transfer(from, to, amount); err != nil {
		panic(err)
	}
}

// Approve authorizes `spender` to pull up to `amount` tokens from the caller.
// Crossing function.
func Approve(cur realm, spender address, amount uint64) {
	owner := caller(cur)
	if !spender.IsValid() {
		panic(errZeroAddress)
	}
	m := allowances[owner]
	if m == nil {
		m = map[address]uint64{}
		allowances[owner] = m
	}
	m[spender] = amount
}

// TransferFrom moves `amount` tokens from `from` to `to`, spending the caller's
// allowance granted by `from`. Crossing function.
func TransferFrom(cur realm, from, to address, amount uint64) {
	spender := caller(cur)
	if !from.IsValid() || !to.IsValid() {
		panic(errZeroAddress)
	}
	allowed := allowances[from][spender]
	if allowed < amount {
		panic(errAllowanceLow)
	}
	if err := transfer(from, to, amount); err != nil {
		panic(err)
	}
	allowances[from][spender] = allowed - amount
}

// transfer is the internal, non-crossing balance mover. Pure logic on package
// state; returns an error rather than panicking so callers control reverts.
func transfer(from, to address, amount uint64) error {
	if amount == 0 {
		return nil
	}
	if balances[from] < amount {
		return errInsufficient
	}
	balances[from] -= amount
	balances[to] += amount
	return nil
}

// BalanceOf returns the token balance of `holder`. Read-only, non-crossing.
func BalanceOf(holder address) uint64 {
	return balances[holder]
}

// Allowance returns how much `spender` may still pull from `owner`.
func Allowance(owner, spender address) uint64 {
	return allowances[owner][spender]
}

// TotalSupply returns the total number of tokens in existence.
func TotalSupply() uint64 {
	return totalSupply
}

// Name returns the token name.
func Name() string { return name }

// Symbol returns the token symbol.
func Symbol() string { return symbol }

// Render produces the gnoweb Markdown view of the token: metadata plus a
// deterministically-ordered table of non-zero balances. Render is NOT a
// crossing function (no `cur realm` parameter).
func Render(path string) string {
	var b strings.Builder

	b.WriteString("# " + name + " (" + symbol + ")\n\n")
	b.WriteString("A minimal ERC-20-style fungible token on gno.land.\n\n")
	b.WriteString("- **Name:** " + name + "\n")
	b.WriteString("- **Symbol:** " + symbol + "\n")
	b.WriteString("- **Total supply:** " + strconv.FormatUint(totalSupply, 10) + "\n\n")

	// Collect and sort holder addresses for deterministic output. Map iteration
	// order is not a stable contract, so we sort the string keys (gno's sort
	// package has no generic Slice; Strings is the deterministic primitive).
	keys := make([]string, 0, len(balances))
	byKey := make(map[string]uint64, len(balances))
	for addr, bal := range balances {
		if bal == 0 {
			continue
		}
		s := addr.String()
		keys = append(keys, s)
		byKey[s] = bal
	}
	sort.Strings(keys)

	b.WriteString("## Balances\n\n")
	if len(keys) == 0 {
		b.WriteString("_No holders yet — call `Mint` to create tokens._\n")
		return b.String()
	}

	b.WriteString("| Address | Amount |\n")
	b.WriteString("| --- | ---: |\n")
	for _, k := range keys {
		b.WriteString("| `" + k + "` | " +
			strconv.FormatUint(byKey[k], 10) + " |\n")
	}

	return b.String()
}
