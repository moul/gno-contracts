// Package erc721 is an idiomatic gno.land port of the Solidity ERC-721
// non-fungible token standard. Each token has a unique integer id owned by
// exactly one address; ids are minted sequentially. Ownership, per-owner
// balances and single-token approvals are kept in ordered avl trees so that
// Render can iterate deterministically.
package erc721

import (
	"strconv"

	"chain"
	"chain/runtime/unsafe"

	"gno.land/p/nt/avl/v0"
)

const (
	name   = "Gno NFT"
	symbol = "GNFT"
)

var (
	owners    avl.Tree // tokenID (zero-padded string) -> address
	balances  avl.Tree // owner address (string) -> uint64
	approvals avl.Tree // tokenID (zero-padded string) -> approved address
	nextID    int64    = 1
	minted    int64    // total tokens ever minted (== live supply, no burn)
)

// key formats a token id into a zero-padded, lexicographically-sortable key.
func key(id int64) string {
	s := strconv.FormatInt(id, 10)
	for len(s) < 12 {
		s = "0" + s
	}
	return s
}

// Mint creates the next token id and assigns it to `to`. Only sequential
// minting is supported (id is returned via the Mint event).
func Mint(cur realm, to address) int64 {
	if !to.IsValid() {
		panic("erc721: mint to invalid address")
	}
	id := nextID
	nextID++
	minted++

	owners.Set(key(id), to)
	balances.Set(to.String(), balanceOf(to)+1)

	chain.Emit("Mint", "to", to.String(), "tokenID", strconv.FormatInt(id, 10))
	return id
}

// Transfer moves token `id` from the caller to `to`. The caller must own the
// token (approvals are cleared on transfer).
func Transfer(cur realm, to address, id int64) {
	if !to.IsValid() {
		panic("erc721: transfer to invalid address")
	}
	caller := unsafe.PreviousRealm().Address()
	from := ownerOf(id) // panics if the token does not exist

	if caller != from {
		// allow the single-token approved operator too
		if approvedOf(id) != caller {
			panic("erc721: caller is neither owner nor approved")
		}
	}
	if from == to {
		panic("erc721: transfer to current owner")
	}

	owners.Set(key(id), to)
	balances.Set(from.String(), balanceOf(from)-1)
	balances.Set(to.String(), balanceOf(to)+1)
	approvals.Remove(key(id)) // clear approval on transfer

	chain.Emit("Transfer", "from", from.String(), "to", to.String(),
		"tokenID", strconv.FormatInt(id, 10))
}

// Approve grants `spender` the right to transfer token `id`. Only the current
// owner may approve.
func Approve(cur realm, spender address, id int64) {
	caller := unsafe.PreviousRealm().Address()
	owner := ownerOf(id)
	if caller != owner {
		panic("erc721: approve caller is not owner")
	}
	approvals.Set(key(id), spender)
	chain.Emit("Approval", "owner", owner.String(), "spender", spender.String(),
		"tokenID", strconv.FormatInt(id, 10))
}

// --- read-only helpers (safe to call from tests and Render) ---

// ownerOf returns the owner of token `id`, panicking if it does not exist.
func ownerOf(id int64) address {
	v := owners.Get(key(id))
	if v == nil {
		panic("erc721: query for nonexistent token")
	}
	return v.(address)
}

// approvedOf returns the approved address for token `id`, or the zero address.
func approvedOf(id int64) address {
	v := approvals.Get(key(id))
	if v == nil {
		return address("")
	}
	return v.(address)
}

// balanceOf returns how many tokens `owner` holds.
func balanceOf(owner address) uint64 {
	v := balances.Get(owner.String())
	if v == nil {
		return 0
	}
	return v.(uint64)
}

// exists reports whether token `id` has been minted (and not since moved away).
func exists(id int64) bool {
	return owners.Has(key(id))
}

// totalSupply returns the number of tokens in circulation.
func totalSupply() int64 { return minted }

// OwnerOf is the exported read-only accessor for ownerOf.
func OwnerOf(id int64) address { return ownerOf(id) }

// BalanceOf is the exported read-only accessor for balanceOf.
func BalanceOf(owner address) uint64 { return balanceOf(owner) }

// TotalSupply is the exported read-only accessor for totalSupply.
func TotalSupply() int64 { return totalSupply() }

// Render displays collection metadata and a token -> owner table.
func Render(path string) string {
	out := "# " + name + " (" + symbol + ")\n\n"
	out += "**Total supply:** " + strconv.FormatInt(totalSupply(), 10) + "\n\n"

	if owners.Size() == 0 {
		out += "_No tokens minted yet._\n"
		return out
	}

	out += "| Token ID | Owner | Approved |\n"
	out += "|---------:|-------|----------|\n"
	owners.Iterate("", "", func(k string, v interface{}) bool {
		owner := v.(address)
		id, _ := strconv.ParseInt(k, 10, 64)
		appr := approvedOf(id)
		apprStr := "—"
		if appr != address("") {
			apprStr = appr.String()
		}
		out += "| " + strconv.FormatInt(id, 10) + " | " +
			owner.String() + " | " + apprStr + " |\n"
		return false
	})
	return out
}
