// Package bitset is a dense, fixed-capacity bit vector as a pure, reusable
// package: a compact set of small non-negative integers with the usual
// set algebra (union, intersection, difference).
//
// Storage is a []uint64 of ceil(n/64) words, so 1024 bits cost 16 words rather
// than 1024 booleans — the reason to reach for this on chain, where every byte
// is paid for.
//
// Capacity is fixed at construction and every operation is bounds-checked
// rather than growing: an out-of-range index is a caller bug, and silently
// growing would make gas unpredictable.
//
// A live demo of this package is at
// [r/moul/x/daily/bitsetdemo](/r/moul/x/daily/bitsetdemo/v1).
package bitset

import "strings"

// MaxBits bounds a BitSet so allocation and iteration stay predictable.
const MaxBits = 1 << 16 // 65536 bits = 1024 words = 8 KiB

// BitSet is a fixed-capacity set of integers in [0, n).
type BitSet struct {
	n     int
	words []uint64
}

// New returns a BitSet holding bits [0, n). n is clamped to [0, MaxBits].
func New(n int) *BitSet {
	if n < 0 {
		n = 0
	}
	if n > MaxBits {
		n = MaxBits
	}
	return &BitSet{n: n, words: make([]uint64, (n+63)/64)}
}

// Cap returns the capacity in bits.
func (b *BitSet) Cap() int { return b.n }

// InRange reports whether i is a valid index.
func (b *BitSet) InRange(i int) bool { return i >= 0 && i < b.n }

// Set turns bit i on and reports whether i was in range.
func (b *BitSet) Set(i int) bool {
	if !b.InRange(i) {
		return false
	}
	b.words[i/64] |= 1 << uint(i%64)
	return true
}

// Clear turns bit i off and reports whether i was in range.
func (b *BitSet) Clear(i int) bool {
	if !b.InRange(i) {
		return false
	}
	b.words[i/64] &^= 1 << uint(i%64)
	return true
}

// Flip inverts bit i and reports whether i was in range.
func (b *BitSet) Flip(i int) bool {
	if !b.InRange(i) {
		return false
	}
	b.words[i/64] ^= 1 << uint(i%64)
	return true
}

// Has reports whether bit i is set. Out of range is false, never a panic:
// membership of something that cannot be a member is simply false.
func (b *BitSet) Has(i int) bool {
	if !b.InRange(i) {
		return false
	}
	return b.words[i/64]&(1<<uint(i%64)) != 0
}

// Count returns the number of set bits (popcount).
func (b *BitSet) Count() int {
	total := 0
	for _, w := range b.words {
		total += popcount(w)
	}
	return total
}

// popcount counts set bits with the classic SWAR trick — no math/bits on gno.
func popcount(x uint64) int {
	n := 0
	for x != 0 {
		x &= x - 1 // clear the lowest set bit
		n++
	}
	return n
}

// Slice returns the set bits in ascending order.
func (b *BitSet) Slice() []int {
	out := []int{}
	for i := 0; i < b.n; i++ {
		if b.Has(i) {
			out = append(out, i)
		}
	}
	return out
}

// Clone returns an independent copy.
func (b *BitSet) Clone() *BitSet {
	c := New(b.n)
	copy(c.words, b.words)
	return c
}

// sameCap reports whether two sets can be combined word-wise.
func sameCap(a, b *BitSet) bool { return a != nil && b != nil && a.n == b.n }

// Union returns a ∪ b, or nil when the capacities differ. Mismatched capacities
// are a caller error rather than something to silently pad.
func Union(a, b *BitSet) *BitSet { return combine(a, b, "or") }

// Intersect returns a ∩ b, or nil when the capacities differ.
func Intersect(a, b *BitSet) *BitSet { return combine(a, b, "and") }

// Difference returns a \ b, or nil when the capacities differ.
func Difference(a, b *BitSet) *BitSet { return combine(a, b, "andnot") }

// SymmetricDifference returns a △ b, or nil when the capacities differ.
func SymmetricDifference(a, b *BitSet) *BitSet { return combine(a, b, "xor") }

func combine(a, b *BitSet, op string) *BitSet {
	if !sameCap(a, b) {
		return nil
	}
	out := New(a.n)
	for i := range a.words {
		switch op {
		case "or":
			out.words[i] = a.words[i] | b.words[i]
		case "and":
			out.words[i] = a.words[i] & b.words[i]
		case "andnot":
			out.words[i] = a.words[i] &^ b.words[i]
		case "xor":
			out.words[i] = a.words[i] ^ b.words[i]
		}
	}
	return out
}

// Equal reports whether two sets have the same capacity and the same bits.
func Equal(a, b *BitSet) bool {
	if !sameCap(a, b) {
		return false
	}
	for i := range a.words {
		if a.words[i] != b.words[i] {
			return false
		}
	}
	return true
}

// String renders the set as '0'/'1' from bit 0 upward, which reads left-to-right
// in index order (note this is the reverse of binary notation).
func (b *BitSet) String() string {
	var sb strings.Builder
	for i := 0; i < b.n; i++ {
		if b.Has(i) {
			sb.WriteByte('1')
		} else {
			sb.WriteByte('0')
		}
	}
	return sb.String()
}

// FromSlice builds a BitSet of capacity n containing the given indices.
// Out-of-range indices are ignored.
func FromSlice(n int, idx []int) *BitSet {
	b := New(n)
	for _, i := range idx {
		b.Set(i)
	}
	return b
}
