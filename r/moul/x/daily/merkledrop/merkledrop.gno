// Package merkledrop is an idiomatic gno.land port of the classic Solidity
// MerkleDistributor airdrop (Uniswap's contract, OpenZeppelin's MerkleProof).
//
// A fixed merkleRoot commits to a set of (address, amount) allocations. A
// recipient proves membership by supplying the sibling hashes on the path from
// their leaf up to the root. Each address may claim exactly once.
//
// Leaf and node hashing use crypto/sha256 (available in the gno stdlib), the
// same primitive Solidity distributors use via keccak — here sha256 keeps the
// off-chain tree builder trivially reproducible. Internal nodes hash the two
// children in sorted order (the OpenZeppelin "commutative" scheme), so proofs
// carry no left/right flags.
//
//	leaf   = sha256(addr.String() + "|" + amount)
//	node   = sha256(min(a,b) || max(a,b))
//
// Balances are pure accounting (uint64); no real coin moves — there is no
// msg.value on gno, so this models the allocation ledger only.
package merkledrop

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"strconv"
	"strings"

	"chain"
	"chain/runtime/unsafe"

	"gno.land/p/nt/avl/v0"
)

// merkleRoot commits to the airdrop allocation set. Generated off-chain with
// the exact scheme above over the four example recipients in README.md.
const merkleRoot = "0d00b73577019dc92924f0ae001d3e1839d51fb358adda2ad1510c39eb82b13f"

// claimed maps claimer address string -> claimed amount (uint64).
var claimed avl.Tree

// totalClaimed is the running sum of all claimed allocations.
var totalClaimed uint64

// leaf computes the tree leaf for an (address, amount) allocation.
func leaf(claimer address, amount uint64) []byte {
	data := claimer.String() + "|" + strconv.FormatUint(amount, 10)
	h := sha256.Sum256([]byte(data))
	return h[:]
}

// hashPair hashes two nodes in sorted order (commutative), so the proof does
// not need to encode child positions.
func hashPair(a, b []byte) []byte {
	var d []byte
	if bytes.Compare(a, b) <= 0 {
		d = append(append(d, a...), b...)
	} else {
		d = append(append(d, b...), a...)
	}
	h := sha256.Sum256(d)
	return h[:]
}

// parseProof splits a comma-separated list of hex hashes into raw 32-byte
// nodes, panicking on any malformed element.
func parseProof(proof string) [][]byte {
	proof = strings.TrimSpace(proof)
	if proof == "" {
		return nil
	}
	parts := strings.Split(proof, ",")
	out := make([][]byte, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p == "" {
			continue
		}
		raw, err := hex.DecodeString(p)
		if err != nil {
			panic("merkledrop: bad proof hash: " + p)
		}
		if len(raw) != sha256.Size {
			panic("merkledrop: proof hash must be 32 bytes: " + p)
		}
		out = append(out, raw)
	}
	return out
}

// computeRoot walks the proof from the given leaf up to a candidate root and
// returns its hex encoding.
func computeRoot(leafHash []byte, proof [][]byte) string {
	node := leafHash
	for _, sib := range proof {
		node = hashPair(node, sib)
	}
	return hex.EncodeToString(node)
}

// Verify reports whether (claimer, amount, proof) resolves to merkleRoot. Pure
// and read-only — safe to call from tests and Render.
func Verify(claimer address, amount uint64, proof string) bool {
	got := computeRoot(leaf(claimer, amount), parseProof(proof))
	return got == merkleRoot
}

// AmountClaimed returns how much the address has already claimed (0 if none).
func AmountClaimed(claimer address) uint64 {
	if !claimed.Has(claimer.String()) {
		return 0
	}
	return claimed.Get(claimer.String()).(uint64)
}

// HasClaimed reports whether the address already claimed.
func HasClaimed(claimer address) bool {
	return claimed.Has(claimer.String())
}

// Claim proves the caller is entitled to `amount` via `proof` (comma-separated
// hex sibling hashes) and marks the allocation claimed. Panics on a bad proof
// or a double claim. Mirrors MerkleDistributor.claim (msg.sender is the caller).
func Claim(cur realm, amount uint64, proof string) {
	caller := unsafe.PreviousRealm().Address()
	if HasClaimed(caller) {
		panic("merkledrop: already claimed")
	}
	if !Verify(caller, amount, proof) {
		panic("merkledrop: invalid proof")
	}
	claimed.Set(caller.String(), amount)
	totalClaimed += amount

	chain.Emit("Claimed",
		"account", caller.String(),
		"amount", strconv.FormatUint(amount, 10),
	)
}

// Render shows the committed root, aggregate stats, and the list of claimers.
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# MerkleDrop\n\n")
	b.WriteString("A fixed Merkle root gates a one-per-address airdrop. Prove your allocation with `Claim(amount, proof)`.\n\n")

	b.WriteString("## Root\n\n")
	b.WriteString("`" + merkleRoot + "`\n\n")

	b.WriteString("## Stats\n\n")
	b.WriteString("- Distinct claimers: " + strconv.Itoa(claimed.Size()) + "\n")
	b.WriteString("- Total claimed: " + strconv.FormatUint(totalClaimed, 10) + "\n\n")

	b.WriteString("## Claimers\n\n")
	if claimed.Size() == 0 {
		b.WriteString("_No claims yet._\n")
		return b.String()
	}
	b.WriteString("| Address | Amount |\n|---|---|\n")
	claimed.Iterate("", "", func(key string, value interface{}) bool {
		b.WriteString("| " + key + " | " + strconv.FormatUint(value.(uint64), 10) + " |\n")
		return false
	})
	return b.String()
}
