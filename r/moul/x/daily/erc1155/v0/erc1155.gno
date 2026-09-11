// Package erc1155 is an idiomatic gno.land port of the Solidity ERC-1155
// multi-token standard. A single realm tracks many distinct token ids, each
// with its own fungible balances. Balances are keyed by (owner, id) in an
// avl.Tree so Render can iterate deterministically.
package erc1155

import (
	"strconv"
	"strings"

	"chain"
	"chain/runtime/unsafe"

	"gno.land/p/nt/avl/v0"
)

// balances maps "<owner>:<id>" -> uint64 amount.
var balances avl.Tree

// supply maps "<id>" -> uint64 total minted for that id.
var supply avl.Tree

func balKey(owner address, id int) string {
	return owner.String() + ":" + strconv.Itoa(id)
}

func supKey(id int) string {
	return strconv.Itoa(id)
}

func getBalance(owner address, id int) uint64 {
	k := balKey(owner, id)
	if !balances.Has(k) {
		return 0
	}
	return balances.Get(k).(uint64)
}

func setBalance(owner address, id int, amount uint64) {
	k := balKey(owner, id)
	if amount == 0 {
		balances.Remove(k)
		return
	}
	balances.Set(k, amount)
}

func getSupply(id int) uint64 {
	k := supKey(id)
	if !supply.Has(k) {
		return 0
	}
	return supply.Get(k).(uint64)
}

// Mint creates `amount` units of token `id` and credits them to `to`.
func Mint(cur realm, to address, id int, amount uint64) {
	if !to.IsValid() {
		panic("erc1155: mint to invalid address")
	}
	if amount == 0 {
		panic("erc1155: mint amount must be > 0")
	}
	setBalance(to, id, getBalance(to, id)+amount)
	supply.Set(supKey(id), getSupply(id)+amount)

	operator := unsafe.PreviousRealm().Address()
	chain.Emit("Mint",
		"operator", operator.String(),
		"to", to.String(),
		"id", strconv.Itoa(id),
		"amount", strconv.FormatUint(amount, 10),
	)
}

// TransferSingle moves `amount` of token `id` from the caller to `to`.
func TransferSingle(cur realm, to address, id int, amount uint64) {
	if !to.IsValid() {
		panic("erc1155: transfer to invalid address")
	}
	if amount == 0 {
		panic("erc1155: transfer amount must be > 0")
	}
	from := unsafe.PreviousRealm().Address()
	fromBal := getBalance(from, id)
	if fromBal < amount {
		panic("erc1155: insufficient balance")
	}
	setBalance(from, id, fromBal-amount)
	setBalance(to, id, getBalance(to, id)+amount)

	chain.Emit("TransferSingle",
		"from", from.String(),
		"to", to.String(),
		"id", strconv.Itoa(id),
		"amount", strconv.FormatUint(amount, 10),
	)
}

// BalanceOf returns the amount of token `id` held by `owner`.
func BalanceOf(owner address, id int) uint64 {
	return getBalance(owner, id)
}

// TotalSupply returns the total amount minted of token `id`.
func TotalSupply(id int) uint64 {
	return getSupply(id)
}

// Render prints a balances table and a per-id supply table.
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# ERC-1155 Multi-Token\n\n")
	b.WriteString("A single realm holding many fungible token ids. ")
	b.WriteString("Balances are keyed by `(owner, id)`.\n\n")

	b.WriteString("## Balances\n\n")
	if balances.Size() == 0 {
		b.WriteString("_No balances yet. Call `Mint` to create tokens._\n\n")
	} else {
		b.WriteString("| Owner | ID | Amount |\n")
		b.WriteString("|---|---|---|\n")
		balances.Iterate("", "", func(key string, value interface{}) bool {
			owner, id := splitBalKey(key)
			b.WriteString("| `" + owner + "` | " + id + " | " +
				strconv.FormatUint(value.(uint64), 10) + " |\n")
			return false
		})
		b.WriteString("\n")
	}

	b.WriteString("## Supply per ID\n\n")
	if supply.Size() == 0 {
		b.WriteString("_No tokens minted._\n")
	} else {
		b.WriteString("| ID | Total Supply |\n")
		b.WriteString("|---|---|\n")
		supply.Iterate("", "", func(key string, value interface{}) bool {
			b.WriteString("| " + key + " | " +
				strconv.FormatUint(value.(uint64), 10) + " |\n")
			return false
		})
	}

	return b.String()
}

// splitBalKey splits a "<owner>:<id>" balance key. The owner (a bech32
// address) contains no ':', so the id is the substring after the last ':'.
func splitBalKey(key string) (owner, id string) {
	i := strings.LastIndex(key, ":")
	if i < 0 {
		return key, ""
	}
	return key[:i], key[i+1:]
}
