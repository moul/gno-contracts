// Package fenwick is a Binary Indexed Tree (Peter Fenwick, 1994): an array of
// int64 that answers a prefix sum and applies a point update in O(log n), with
// no extra storage beyond the array itself.
//
// The tradeoff it occupies is the whole reason to reach for one. A plain slice
// updates in O(1) and sums in O(n). A slice of running totals sums in O(1) and
// updates in O(n). A Fenwick tree does both in O(log n), which is what a realm
// wants when reads and writes are interleaved: a scoreboard written by every
// player and read by every render.
//
// The operation that actually justifies the package is [Tree.SearchPrefix]: the
// smallest index whose prefix sum exceeds a target, in O(log n), by descending
// the tree rather than scanning it. That is the primitive behind a
// stake-weighted draw (pick a number below Total, ask which holder owns it) and
// behind a leaderboard's rank lookup. Prefix sums on their own would not be
// worth a data structure.
//
// Reads are total and writes are strict, deliberately: see the package README.
//
// A live demo of this package is at
// [r/moul/x/daily/fenwickdemo](/r/moul/x/daily/fenwickdemo/v0).
package fenwick

// MaxSize bounds the number of slots so a caller cannot size the tree from
// unbounded user input and make the allocation itself the attack. It is not a
// gas figure: a query costs O(log n) regardless, and the cap exists so the one
// O(n) operation in the package, construction, stays bounded.
const MaxSize = 65536

// Tree is a Binary Indexed Tree over int64 values, addressed 0-based.
//
// The zero value is not usable; build one with [New] or [FromSlice].
type Tree struct {
	n int
	// t is 1-based internally: t[i] holds the sum of the LowBit(i) values
	// ending at i. Index 0 is unused, which is what makes the bit tricks work.
	t []int64
}

// New returns a Tree of n zero-valued slots.
//
// It panics if n is negative or above [MaxSize]: both are programmer errors
// that a caller cannot recover from, and a silently clamped size would hand
// back a tree that disagrees with the caller about its own length.
func New(n int) *Tree {
	if n < 0 {
		panic("fenwick: negative size")
	}
	if n > MaxSize {
		panic("fenwick: size above MaxSize")
	}
	return &Tree{n: n, t: make([]int64, n+1)}
}

// FromSlice returns a Tree holding vals, built in O(n) rather than by n
// successive Add calls, which would cost O(n log n).
//
// The slice is copied; later writes to vals do not reach the tree.
func FromSlice(vals []int64) *Tree {
	tr := New(len(vals))
	// Seed each slot, then push it into its parent once. Every slot is visited
	// exactly once, which is the whole O(n) construction.
	for i, v := range vals {
		tr.t[i+1] += v
		if parent := (i + 1) + lowBit(i+1); parent <= tr.n {
			tr.t[parent] += tr.t[i+1]
		}
	}
	return tr
}

// Len returns the number of slots.
func (tr *Tree) Len() int { return tr.n }

// Add adds delta to the value at i.
//
// It panics if i is out of range. A write is a transaction: failing loudly is
// the correct outcome, and the caller still has the chance to abort.
func (tr *Tree) Add(i int, delta int64) {
	if i < 0 || i >= tr.n {
		panic("fenwick: index out of range")
	}
	for j := i + 1; j <= tr.n; j += lowBit(j) {
		tr.t[j] += delta
	}
}

// Set replaces the value at i, returning the value it displaced.
//
// It panics if i is out of range, for the same reason [Tree.Add] does.
func (tr *Tree) Set(i int, v int64) int64 {
	old := tr.At(i)
	if i < 0 || i >= tr.n {
		panic("fenwick: index out of range")
	}
	tr.Add(i, v-old)
	return old
}

// Prefix returns the sum of the first i values, that is of [0, i).
//
// It is total: i is clamped into [0, Len], so Prefix(-5) is 0 and Prefix(1e9)
// is Total. Reads are what Render calls, and a panicking Render is a page that
// can never be displayed again, on a path that can never be redeployed.
func (tr *Tree) Prefix(i int) int64 {
	if i > tr.n {
		i = tr.n
	}
	var sum int64
	for ; i > 0; i -= lowBit(i) {
		sum += tr.t[i]
	}
	return sum
}

// Range returns the sum of [lo, hi). It is total: bounds are clamped, and an
// empty or inverted range is 0.
func (tr *Tree) Range(lo, hi int) int64 {
	if lo < 0 {
		lo = 0
	}
	if hi > tr.n {
		hi = tr.n
	}
	if lo >= hi {
		return 0
	}
	return tr.Prefix(hi) - tr.Prefix(lo)
}

// At returns the value at i, or 0 if i is out of range. Total, like the other
// reads.
func (tr *Tree) At(i int) int64 {
	if i < 0 || i >= tr.n {
		return 0
	}
	return tr.Range(i, i+1)
}

// Total returns the sum of every value.
func (tr *Tree) Total() int64 { return tr.Prefix(tr.n) }

// Slice materializes the tree back into a plain slice, in O(n log n).
//
// It exists for rendering and for tests. A hot path should not call it.
func (tr *Tree) Slice() []int64 {
	out := make([]int64, tr.n)
	for i := 0; i < tr.n; i++ {
		out[i] = tr.At(i)
	}
	return out
}

// SearchPrefix returns the smallest index i for which Prefix(i+1) > target,
// or Len if no prefix exceeds it. It runs in O(log n) by descending the tree.
//
// With non-negative values this is the weighted select: draw a target in
// [0, Total) and SearchPrefix names the slot that owns it, each slot chosen in
// proportion to its value. A zero-valued slot can never be selected, which is
// the property that makes it usable for a stake-weighted draw.
//
// It is total, and a negative target returns 0.
//
// The result is only meaningful when every value is non-negative: with a
// negative value in the tree the prefix sums stop increasing and "the smallest
// index whose prefix exceeds target" stops being well defined. The package does
// not forbid negative values, because Add with a negative delta is the ordinary
// way to decrement a counter; it is SearchPrefix alone that needs them absent.
func (tr *Tree) SearchPrefix(target int64) int {
	if target < 0 {
		return 0
	}
	pos := 0
	// Walk the powers of two downward, largest first. At each step, take the
	// jump if the value it would accumulate still does not exceed target.
	for step := highBit(tr.n); step > 0; step >>= 1 {
		if next := pos + step; next <= tr.n && tr.t[next] <= target {
			pos = next
			target -= tr.t[next]
		}
	}
	return pos
}

// lowBit returns the lowest set bit of i, the range width the slot covers.
func lowBit(i int) int { return i & (-i) }

// highBit returns the highest power of two that is <= n, or 0 when n is 0.
func highBit(n int) int {
	p := 1
	for p<<1 <= n {
		p <<= 1
	}
	if n == 0 {
		return 0
	}
	return p
}

// Covers returns the half-open range [lo, hi) of 0-based slots that the
// internal node at 1-based position i summarizes, which is what makes the
// structure legible rather than magic. It is exported for the demo and for
// anyone trying to see the shape; it is not needed to use the tree.
//
// It returns (0, 0) when i is outside [1, Len].
func (tr *Tree) Covers(i int) (int, int) {
	if i < 1 || i > tr.n {
		return 0, 0
	}
	return i - lowBit(i), i
}
