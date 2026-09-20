// Package merkle builds and verifies Merkle inclusion proofs on gno.land.
//
// It wraps the `crypto/merkle` stdlib, which is native (implemented in Go,
// gas-metered) and shipped with the chain, and which had no callers anywhere
// before this package. Verification is a single native call, so it costs about
// a seventh of the equivalent hand-rolled loop in Gno.
//
// # The scheme
//
// The tree is the Tendermint simple tree, byte-for-byte the one tm2 uses for
// block headers, so a proof produced here verifies against any Tendermint
// tooling and vice versa. Two properties matter and neither is optional:
//
//   - Leaves and inner nodes are DOMAIN SEPARATED. A leaf hashes as
//     SHA256(0x00 || leaf), an inner node as SHA256(0x01 || left || right).
//     Without that tag an attacker who can choose a 64-byte leaf preimage can
//     present an inner node as if it were a leaf: the second-preimage attack.
//     Schemes that hash leaves bare (OpenZeppelin's `MerkleProof`,
//     merkletreejs defaults, `p/demo/merkle`) are safe only as long as no leaf
//     preimage can be exactly 64 bytes, which is an accident of encoding
//     rather than a property of the design.
//   - Proofs are INDEX BOUND. A proof carries its leaf index and the total
//     leaf count, and the verifier recomputes the tree shape from them. A
//     proof for index i cannot be replayed at index j, and a proof of the
//     wrong length is rejected rather than folded.
//
// The tree is NOT padded to a power of two. Following Tendermint, a tree of n
// leaves splits at the largest power of two below n, which makes the shape a
// function of n alone. Duplicating or promoting an odd trailing leaf, as
// Bitcoin and merkletreejs do, lets two different leaf sets produce one root.
//
// # Bounds
//
// Verify refuses proofs deeper than MaxDepth. An unbounded sibling list is a
// loop whose length an untrusted caller picks; the caller pays the gas, but
// there is no reason to accept 10,000 siblings for a tree that cannot hold
// more than 2^64 leaves.
//
// # Reproducing a tree off chain
//
// Any Tendermint implementation agrees with this one. In Go:
//
//	import "github.com/gnolang/gno/tm2/pkg/crypto/merkle"
//	root, proofs := merkle.SimpleProofsFromByteSlices(leaves)
//
// # What this package cannot do
//
// It verifies a leaf against a root YOU SUPPLY. A realm has no access to the
// block header or the app hash (`chain/runtime` exposes only ChainID,
// ChainDomain, ChainHeight and GetSessionInfo), so no realm can check that a
// root is the chain's own. Anything built on this is trust-minimised relative
// to a committed root, never trustless. See `r/moul/x/provable/v0` for what
// gno.land can and cannot prove about itself.
//
// Live demo: gno.land/r/moul/x/provable/v0
package merkle

import (
	"crypto/merkle"
	"encoding/hex"
	"errors"
	"strings"
)

// HashSize is the length in bytes of every node hash (SHA256).
const HashSize = 32

// MaxDepth caps the sibling count Verify will fold. A tree of 2^64 leaves has
// depth 64, so nothing legitimate ever exceeds it.
const MaxDepth = 64

var (
	ErrEmptyTree    = errors.New("merkle: tree has no leaves")
	ErrIndexRange   = errors.New("merkle: leaf index out of range")
	ErrProofTooDeep = errors.New("merkle: proof deeper than MaxDepth")
	ErrBadHex       = errors.New("merkle: sibling is not valid hex")
	ErrBadHashSize  = errors.New("merkle: sibling is not 32 bytes")
)

// LeafHash returns SHA256(0x00 || leaf), the Tendermint leaf hash.
func LeafHash(leaf []byte) []byte { return merkle.LeafHash(leaf) }

// InnerHash returns SHA256(0x01 || left || right), the Tendermint inner hash.
func InnerHash(left, right []byte) []byte { return merkle.InnerHash(left, right) }

// Proof is an inclusion proof for one leaf of a tree of Total leaves.
//
// Siblings are ordered leaf first, root last: Siblings[0] is the leaf's
// immediate sibling and the final entry is the other child of the root. This
// is Tendermint's "aunts" order.
type Proof struct {
	Index    int
	Total    int
	Siblings [][]byte
}

// Tree is an immutable Merkle tree over a fixed list of leaves.
//
// It holds the leaves, so it is meant to be built inside one call (from
// arguments, or from a bounded realm collection) rather than kept in realm
// storage. For an append-only log that stores only O(log n) state, use
// gno.land/p/moul/x/mmr/v0 instead.
type Tree struct {
	leaves [][]byte
	root   []byte
}

// New builds a tree over leaves, in the order given. The order is part of the
// commitment: the same set in a different order is a different root.
func New(leaves [][]byte) *Tree {
	cp := make([][]byte, len(leaves))
	for i, l := range leaves {
		b := make([]byte, len(l))
		copy(b, l)
		cp[i] = b
	}
	t := &Tree{leaves: cp}
	if len(cp) > 0 {
		t.root = merkle.HashFromByteSlices(encodeSlices(cp))
	}
	return t
}

// Size returns the number of leaves.
func (t *Tree) Size() int { return len(t.leaves) }

// Root returns the tree root. It is nil for an empty tree, matching
// Tendermint, where the root of nothing is nothing rather than a hash of
// nothing.
//
// The nil is produced here rather than passed through: a native that returns
// Go nil hands gno back a NON-NIL zero-length slice, so `== nil` on a value
// straight out of crypto/merkle never fires. Test len(), not nil, on anything
// that crossed that boundary.
func (t *Tree) Root() []byte { return t.root }

// RootHex returns Root hex-encoded, the form to paste into a realm call.
func (t *Tree) RootHex() string { return hex.EncodeToString(t.root) }

// Proof returns the inclusion proof for the leaf at index.
func (t *Tree) Proof(index int) (Proof, error) {
	if len(t.leaves) == 0 {
		return Proof{}, ErrEmptyTree
	}
	if index < 0 || index >= len(t.leaves) {
		return Proof{}, ErrIndexRange
	}
	return Proof{
		Index:    index,
		Total:    len(t.leaves),
		Siblings: aunts(t.leaves, index),
	}, nil
}

// aunts collects the sibling hashes on the path from leaves[index] to the
// root, leaf first. It mirrors Tendermint's split-point recursion exactly; any
// divergence here produces proofs the native verifier rejects.
func aunts(leaves [][]byte, index int) [][]byte {
	if len(leaves) <= 1 {
		return nil
	}
	k := splitPoint(len(leaves))
	if index < k {
		sub := aunts(leaves[:k], index)
		return append(sub, subtreeRoot(leaves[k:]))
	}
	sub := aunts(leaves[k:], index-k)
	return append(sub, subtreeRoot(leaves[:k]))
}

func subtreeRoot(leaves [][]byte) []byte {
	return merkle.HashFromByteSlices(encodeSlices(leaves))
}

// splitPoint returns the largest power of two strictly less than length.
func splitPoint(length int) int {
	if length < 2 {
		return 0
	}
	k := 1
	for k<<1 < length {
		k <<= 1
	}
	return k
}

// Verify reports whether leaf really sits at p.Index of a tree of p.Total
// leaves whose root is root. It is one native call plus the bounds checks.
//
// Every failure is a false rather than a panic, so a realm can decide whether
// a bad proof is a revert or a branch.
func (p Proof) Verify(root, leaf []byte) bool {
	if len(root) != HashSize || p.Total <= 0 || p.Index < 0 || p.Index >= p.Total {
		return false
	}
	if len(p.Siblings) > MaxDepth {
		return false
	}
	flat := make([]byte, 0, len(p.Siblings)*HashSize)
	for _, s := range p.Siblings {
		if len(s) != HashSize {
			return false
		}
		flat = append(flat, s...)
	}
	return merkle.VerifySimpleProof(root, leaf, p.Index, p.Total, flat)
}

// Hex renders the siblings as a comma-separated hex list, the form a user
// pastes into a transaction. Index and Total travel as their own arguments.
func (p Proof) Hex() string {
	parts := make([]string, len(p.Siblings))
	for i, s := range p.Siblings {
		parts[i] = hex.EncodeToString(s)
	}
	return strings.Join(parts, ",")
}

// ParseProof rebuilds a Proof from the arguments of a realm call. An empty or
// whitespace-only sibling list is valid: it is the proof for a one-leaf tree.
func ParseProof(index, total int, hexSiblings string) (Proof, error) {
	p := Proof{Index: index, Total: total}
	s := strings.TrimSpace(hexSiblings)
	if s == "" {
		return p, nil
	}
	parts := strings.Split(s, ",")
	if len(parts) > MaxDepth {
		return Proof{}, ErrProofTooDeep
	}
	for _, raw := range parts {
		raw = strings.TrimSpace(raw)
		if raw == "" {
			continue
		}
		b, err := hex.DecodeString(raw)
		if err != nil {
			return Proof{}, ErrBadHex
		}
		if len(b) != HashSize {
			return Proof{}, ErrBadHashSize
		}
		p.Siblings = append(p.Siblings, b)
	}
	return p, nil
}

// VerifySorted folds a commutative, sorted-pair proof: node = SHA256(min || max)
// at every step, which is what OpenZeppelin's MerkleProof and merkletreejs
// produce. Provided for verifying trees built by existing Solidity tooling.
//
// PREFER Proof.Verify. This scheme is strictly weaker:
//
//   - It is not domain separated, so it is sound only while no leaf preimage
//     can be 64 bytes long. Pass an ALREADY HASHED leaf, and double-hash it if
//     the producer does (OpenZeppelin's StandardMerkleTree does).
//   - It is not index bound, so a proof carries no position and the fold
//     accepts any depth up to MaxDepth.
//
// leafHash must be the 32-byte hash of the leaf, not the leaf.
func VerifySorted(root, leafHash []byte, siblings [][]byte) bool {
	if len(root) != HashSize || len(leafHash) != HashSize {
		return false
	}
	if len(siblings) > MaxDepth {
		return false
	}
	node := leafHash
	for _, s := range siblings {
		if len(s) != HashSize {
			return false
		}
		node = hashSortedPair(node, s)
	}
	return equal(node, root)
}
