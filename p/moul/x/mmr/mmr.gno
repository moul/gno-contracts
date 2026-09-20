// Package mmr implements a Merkle Mountain Range: an append-only log with a
// root that updates in O(log n) and inclusion proofs of O(log n) size.
//
// # Why not a plain Merkle tree
//
// gno.land/p/moul/x/merkle/v0 commits to a FIXED list. Adding a leaf means
// rebuilding from every leaf, which on chain means re-reading the whole set
// and re-hashing it, every time. An MMR never rebuilds: an append hashes at
// most log2(n) times and touches nothing else.
//
// That is the shape any on-chain log wants. A wiki committing to its revision
// history, a forge committing to its objects, an agent realm committing to the
// receipts it issued: all append, none rewrite.
//
// # The structure
//
// An MMR is a list of perfect binary trees ("mountains") of strictly
// decreasing height, one per set bit of the leaf count. Eleven leaves is
// 8 + 2 + 1, so three mountains of height 3, 1 and 0. Appending a leaf pushes
// a height-0 mountain and merges equal-height neighbours, exactly like
// incrementing a binary counter.
//
// The root is the peaks "bagged" right to left:
//
//	root = InnerHash(p0, InnerHash(p1, InnerHash(p2, …)))
//
// Hashing is gno.land/p/moul/x/merkle/v0's, which is Tendermint's: leaves are
// tagged 0x00 and inner nodes 0x01. Leaf and inner preimages therefore cannot
// collide, so the second-preimage forgery that works against untagged schemes
// does not apply here. See that package for the worked attack.
//
// # This IS the Tendermint tree
//
// The root above equals the Tendermint simple-tree root over the same leaves,
// at every size and not merely at powers of two. Tendermint splits an n-leaf
// tree at the largest power of two below n: that left half is exactly the
// first mountain, and the right half recurses through the remaining set bits,
// which is exactly the bagging. The two constructions coincide.
//
// So this package is a drop-in INCREMENTAL BUILDER for Tendermint roots.
// Append in O(log n) on chain and hand out a root that any Tendermint verifier
// accepts; proofs cross over in both directions, which
// TestMerkleProofVerifiesAgainstMMRRoot pins. Use merkle.New when the leaf set
// is fixed and you want the simpler proof encoding, use this when the log
// grows.
//
// # Proofs are bound to position and to size
//
// A Proof carries the leaf index and the leaf count the MMR had when it was
// issued. The verifier recomputes the whole peak structure from that count,
// which fixes the number of peaks, which mountain holds the leaf, the local
// index inside it, and therefore the exact expected length of every component
// of the proof. A proof cannot be replayed at another index, against another
// size, or padded.
//
// Because the root changes on every append, a proof is valid against the root
// at its own Total and no other. A realm that wants old proofs to keep
// verifying must keep the historical roots; Roots grow by one 32-byte hash per
// append, which is the price of an auditable log.
//
// # Storage
//
// Append stores one node per leaf plus one per merge, so 2n-popcount(n) hashes
// for n leaves, under 64 bytes per leaf amortised. That is what on-chain proof
// generation costs. A realm that only ever needs to VERIFY proofs, with the
// tree living off chain, should store the root alone and use
// gno.land/p/moul/x/merkle/v0's Verify instead.
//
// Live demo: gno.land/r/moul/x/provable/v0
package mmr

import (
	"encoding/hex"
	"errors"

	"gno.land/p/moul/x/merkle/v0"
)

// HashSize is the length in bytes of every node hash.
const HashSize = merkle.HashSize

// MaxPeaks caps the peak count a Proof may claim. A 64-peak MMR would hold
// more than 2^64 leaves.
const MaxPeaks = 64

var (
	ErrEmpty      = errors.New("mmr: log is empty")
	ErrIndexRange = errors.New("mmr: leaf index out of range")
	ErrBadHex     = errors.New("mmr: hash is not valid hex")
	ErrBadSize    = errors.New("mmr: hash is not 32 bytes")
	ErrTooManyPeaks = errors.New("mmr: more peaks than MaxPeaks")
)

// peak is one mountain: the position of its root in nodes, and its height.
type peak struct {
	pos    int
	height int
}

// MMR is an append-only Merkle mountain range.
//
// The zero value is an empty, ready-to-use log.
type MMR struct {
	nodes  [][]byte // every node, in postorder: [left subtree][right subtree][root]
	peaks  []peak
	leaves int
}

// New returns an empty MMR.
func New() *MMR { return &MMR{} }

// Size returns the number of leaves appended so far.
func (m *MMR) Size() int { return m.leaves }

// Nodes returns the number of stored hashes, leaves and merges together. Use
// it to reason about storage growth.
func (m *MMR) Nodes() int { return len(m.nodes) }

// Append adds a leaf and returns its index. O(log n) hashes, no rebuild.
func (m *MMR) Append(leaf []byte) int {
	index := m.leaves
	m.nodes = append(m.nodes, merkle.LeafHash(leaf))
	m.peaks = append(m.peaks, peak{pos: len(m.nodes) - 1, height: 0})
	for len(m.peaks) >= 2 {
		right := m.peaks[len(m.peaks)-1]
		left := m.peaks[len(m.peaks)-2]
		if left.height != right.height {
			break
		}
		m.nodes = append(m.nodes, merkle.InnerHash(m.nodes[left.pos], m.nodes[right.pos]))
		m.peaks = m.peaks[:len(m.peaks)-2]
		m.peaks = append(m.peaks, peak{pos: len(m.nodes) - 1, height: left.height + 1})
	}
	m.leaves++
	return index
}

// Root returns the current root, nil while the log is empty.
func (m *MMR) Root() []byte {
	if len(m.peaks) == 0 {
		return nil
	}
	return bag(m.peakHashes())
}

// RootHex returns Root hex-encoded.
func (m *MMR) RootHex() string { return hex.EncodeToString(m.Root()) }

// PeakHashes returns the current peak hashes, left to right. This is the whole
// state a verifier needs, and it is O(log n).
func (m *MMR) PeakHashes() [][]byte { return m.peakHashes() }

func (m *MMR) peakHashes() [][]byte {
	out := make([][]byte, len(m.peaks))
	for i, p := range m.peaks {
		out[i] = m.nodes[p.pos]
	}
	return out
}

// bag folds peaks right to left: InnerHash(p0, InnerHash(p1, …)).
func bag(peaks [][]byte) []byte {
	if len(peaks) == 0 {
		return nil
	}
	acc := peaks[len(peaks)-1]
	for i := len(peaks) - 2; i >= 0; i-- {
		acc = merkle.InnerHash(peaks[i], acc)
	}
	return acc
}

// Proof is an inclusion proof for one leaf of a log that held Total leaves.
//
// Path holds the sibling hashes inside the leaf's own mountain, leaf first.
// Before and After hold the other peak hashes, in left-to-right order.
type Proof struct {
	Index  int
	Total  int
	Path   [][]byte
	Before [][]byte
	After  [][]byte
}

// Proof returns the inclusion proof for the leaf at index, against the current
// root.
func (m *MMR) Proof(index int) (Proof, error) {
	if m.leaves == 0 {
		return Proof{}, ErrEmpty
	}
	if index < 0 || index >= m.leaves {
		return Proof{}, ErrIndexRange
	}
	j, local := locate(m.leaves, index)
	hashes := m.peakHashes()
	return Proof{
		Index:  index,
		Total:  m.leaves,
		Path:   m.pathIn(m.peaks[j], local),
		Before: hashes[:j],
		After:  hashes[j+1:],
	}, nil
}

// pathIn walks down the perfect tree rooted at p, collecting the sibling at
// each level, and returns them leaf first.
//
// The layout is postorder, so for a node at position pos and height h the
// right child root sits at pos-1 and the left child root at pos-1-(2^h - 1),
// a perfect subtree of height h-1 holding 2^h - 1 nodes.
func (m *MMR) pathIn(p peak, local int) [][]byte {
	var out [][]byte
	pos, h := p.pos, p.height
	for h > 0 {
		rightRoot := pos - 1
		leftRoot := pos - 1 - ((1 << uint(h)) - 1)
		half := 1 << uint(h-1)
		if local < half {
			out = append([][]byte{m.nodes[rightRoot]}, out...)
			pos = leftRoot
		} else {
			out = append([][]byte{m.nodes[leftRoot]}, out...)
			pos = rightRoot
			local -= half
		}
		h--
	}
	return out
}
