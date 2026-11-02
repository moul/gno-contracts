// Package segmenttree answers "what is the sum, the minimum or the maximum
// over slots lo..hi" in O(log n), while still letting any single slot be
// rewritten in O(log n), as a pure, reusable package.
//
// It is the structure a realm wants when both halves of that sentence are
// true. A plain slice answers a range in O(n), a running prefix-sum array
// answers it in O(1) but costs O(n) to repair after one write, and
// [p/moul/x/daily/fenwick](/p/moul/x/daily/fenwick/v0) gives prefix sums
// cheaply but cannot do minimum or maximum, because those have no inverse to
// subtract with. A segment tree keeps the combined value of every subrange, so
// the three questions are the same walk with a different combine.
//
// The combine is an [Op] constant rather than a function value, on purpose: a
// realm persists its tree, and a struct holding a closure is not something a
// realm can store. See [New].
//
// Nothing here panics. Every accessor reports an out-of-range request with a
// false second value instead, because a Render that panics is a page nobody
// can ever read again and a public realm path cannot be redeployed.
//
// A live demo of this package is at
// [r/moul/x/daily/segmenttreedemo](/r/moul/x/daily/segmenttreedemo/v0).
package segmenttree

// maxInt64 and minInt64 are spelled out rather than imported, so the package
// keeps the empty import list that makes it trivially portable.
const (
	maxInt64 = int64(^uint64(0) >> 1)
	minInt64 = -maxInt64 - 1
)

// Op is how two neighbouring ranges are folded into their parent.
//
// It is an enum and not a func field because a realm stores its tree, and a
// persisted object may not hold a function value. The price is that a caller
// cannot supply its own monoid; the three below are what a chain actually
// asks for.
type Op int

const (
	// Sum adds the two ranges. Identity 0.
	Sum Op = iota
	// Min keeps the smaller. Identity is the largest int64.
	Min
	// Max keeps the larger. Identity is the smallest int64.
	Max
)

// String names the op, for a Render or an error message. An unrecognised value
// reads as "sum", which is what [New] turns it into.
func (op Op) String() string {
	switch op {
	case Min:
		return "min"
	case Max:
		return "max"
	default:
		return "sum"
	}
}

// Identity is the value that leaves the op unchanged: the answer to an empty
// range, and what the unused padding slots hold.
//
// It is exported because a caller reading a false second value from [Tree.Query]
// still gets a number back, and this is the number it got.
func (op Op) Identity() int64 {
	switch op {
	case Min:
		return maxInt64
	case Max:
		return minInt64
	default:
		return 0
	}
}

// Node is one node of the tree as [Tree.Nodes] reports it: the half-open leaf
// range it covers and the combined value over that range. Level 0 is the root.
//
// It exists so a demo or a debugging page can show the structure instead of
// describing it. The range is clamped to [Tree.Len], so padding never leaks out.
type Node struct {
	Level  int
	Lo, Hi int
	Value  int64
}

// Tree is a segment tree over a fixed number of int64 slots. Build one with
// [New] or one of the three named constructors; the zero value is an empty
// tree whose every query reports not-ok, which is a usable thing to render.
type Tree struct {
	op   Op
	n    int     // slots the caller asked for
	size int     // n rounded up to a power of two, 0 when n is 0
	node []int64 // 2*size; leaves at [size, 2*size), index 0 unused
}

// New builds a tree over a copy of values, folded with op.
//
// The values are copied: a caller that keeps mutating its own slice afterwards
// would otherwise have a tree whose internal nodes no longer match its leaves,
// which is the one failure mode of this structure that is invisible until a
// query returns a plausible wrong number.
//
// An unrecognised op becomes [Sum]. A constructor that panicked would take down
// the realm's init, and every op is a correct answer to some question.
func New(op Op, values []int64) *Tree {
	if op != Sum && op != Min && op != Max {
		op = Sum
	}
	t := &Tree{op: op, n: len(values)}
	if t.n == 0 {
		return t
	}

	// Round up to a power of two so every node covers an aligned range, which
	// is what makes Nodes reportable. The padding holds the identity, so it can
	// never become the answer to a min or a max.
	t.size = 1
	for t.size < t.n {
		t.size <<= 1
	}
	t.node = make([]int64, 2*t.size)
	id := op.Identity()
	for i := 0; i < t.size; i++ {
		if i < t.n {
			t.node[t.size+i] = values[i]
		} else {
			t.node[t.size+i] = id
		}
	}
	for i := t.size - 1; i >= 1; i-- {
		t.node[i] = t.combine(t.node[2*i], t.node[2*i+1])
	}
	return t
}

// NewSum is New with [Sum].
func NewSum(values []int64) *Tree { return New(Sum, values) }

// NewMin is New with [Min].
func NewMin(values []int64) *Tree { return New(Min, values) }

// NewMax is New with [Max].
func NewMax(values []int64) *Tree { return New(Max, values) }

// combine folds two values with the tree's op.
func (t *Tree) combine(a, b int64) int64 {
	switch t.op {
	case Min:
		if b < a {
			return b
		}
		return a
	case Max:
		if b > a {
			return b
		}
		return a
	default:
		return a + b
	}
}

// Op reports how this tree folds ranges.
func (t *Tree) Op() Op { return t.op }

// Len reports how many slots the tree holds.
func (t *Tree) Len() int { return t.n }

// Depth reports how many levels [Tree.Nodes] walks, root included. It is
// 0 for an empty tree and grows by one every time Len crosses a power of two.
func (t *Tree) Depth() int {
	d := 0
	for w := t.size; w >= 1; w >>= 1 {
		d++
	}
	return d
}

// At returns the value in slot i, and false when i is outside the tree.
func (t *Tree) At(i int) (int64, bool) {
	if i < 0 || i >= t.n {
		return t.op.Identity(), false
	}
	return t.node[t.size+i], true
}

// Set rewrites slot i and repairs the path up to the root, in O(log n).
// It reports false, and changes nothing, when i is outside the tree.
func (t *Tree) Set(i int, v int64) bool {
	if i < 0 || i >= t.n {
		return false
	}
	j := t.size + i
	t.node[j] = v
	for j >>= 1; j >= 1; j >>= 1 {
		t.node[j] = t.combine(t.node[2*j], t.node[2*j+1])
	}
	return true
}

// Add offsets slot i by delta. It is [Tree.Set] of the current value plus
// delta, so it means what a caller expects under [Sum] and is still a plain
// edit under [Min] and [Max].
func (t *Tree) Add(i int, delta int64) bool {
	v, ok := t.At(i)
	if !ok {
		return false
	}
	return t.Set(i, v+delta)
}

// Query folds the half-open range [lo, hi) and reports true.
//
// It reports false, with the op's identity as the value, for a range that is
// empty, reversed or outside the tree. A caller that already validated its
// bounds can ignore the second value; one rendering a page cannot, because
// "the minimum is 9223372036854775807" is a worse answer than "no slots".
func (t *Tree) Query(lo, hi int) (int64, bool) {
	if t.n == 0 || lo < 0 || hi > t.n || lo >= hi {
		return t.op.Identity(), false
	}
	acc := t.op.Identity()
	// Bottom-up: walk the two frontiers towards the root, absorbing a node
	// whenever it is the odd one out and therefore fully inside the range.
	for l, r := lo+t.size, hi+t.size; l < r; l, r = l>>1, r>>1 {
		if l&1 == 1 {
			acc = t.combine(acc, t.node[l])
			l++
		}
		if r&1 == 1 {
			r--
			acc = t.combine(acc, t.node[r])
		}
	}
	return acc, true
}

// Total folds every slot. It is [Tree.Query] over the whole tree, so an empty
// tree reports false rather than the identity dressed up as an answer.
func (t *Tree) Total() (int64, bool) { return t.Query(0, t.n) }

// Values returns the slots in order, as a copy. The copy is the point: a
// caller cannot reach the leaves and leave the internal nodes stale.
func (t *Tree) Values() []int64 {
	out := make([]int64, t.n)
	for i := 0; i < t.n; i++ {
		out[i] = t.node[t.size+i]
	}
	return out
}

// Nodes returns every node that covers at least one real slot, breadth-first,
// root first. Ranges are half-open and clamped to [Tree.Len], so a tree whose
// length is not a power of two reports the ranges a reader expects rather than
// the padded ones it stores.
func (t *Tree) Nodes() []Node {
	if t.n == 0 {
		return nil
	}
	out := []Node{}
	for level := 0; (1 << level) <= t.size; level++ {
		span := t.size >> level
		for j := 0; j < (1 << level); j++ {
			lo := j * span
			if lo >= t.n {
				continue // pure padding, and nothing a reader should see
			}
			hi := lo + span
			if hi > t.n {
				hi = t.n
			}
			out = append(out, Node{
				Level: level,
				Lo:    lo,
				Hi:    hi,
				Value: t.node[(1<<level)+j],
			})
		}
	}
	return out
}
