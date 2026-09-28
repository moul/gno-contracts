package fenwick

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// naive is the reference implementation every structural test is checked
// against: the obvious O(n) loop nobody would ship. A data structure whose
// whole claim is "same answers, better complexity" is only worth trusting if
// the same answers half is pinned against something too simple to be wrong.
type naive []int64

func (s naive) prefix(i int) int64 {
	if i > len(s) {
		i = len(s)
	}
	var sum int64
	for k := 0; k < i; k++ {
		sum += s[k]
	}
	return sum
}

func (s naive) searchPrefix(target int64) int {
	if target < 0 {
		return 0
	}
	var run int64
	for i, v := range s {
		run += v
		if run > target {
			return i
		}
	}
	return len(s)
}

func TestPrefixMatchesNaive(t *testing.T) {
	cases := []struct {
		name string
		vals []int64
	}{
		{"empty", []int64{}},
		{"one", []int64{7}},
		{"two", []int64{3, 4}},
		// A power of two and one past it: the tree's shape changes at the
		// boundary, and an off-by-one in lowBit only shows on one side of it.
		{"eight", []int64{1, 2, 3, 4, 5, 6, 7, 8}},
		{"nine", []int64{1, 2, 3, 4, 5, 6, 7, 8, 9}},
		{"zeros", []int64{0, 0, 0, 0, 0}},
		{"negatives", []int64{5, -3, 2, -10, 40}},
		{"large", []int64{1 << 40, 1 << 40, -(1 << 41)}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			tr := FromSlice(tc.vals)
			ref := naive(tc.vals)
			uassert.Equal(t, len(tc.vals), tr.Len())
			for i := 0; i <= len(tc.vals); i++ {
				uassert.Equal(t, ref.prefix(i), tr.Prefix(i))
			}
			for i := range tc.vals {
				uassert.Equal(t, tc.vals[i], tr.At(i))
			}
			uassert.Equal(t, ref.prefix(len(tc.vals)), tr.Total())
		})
	}
}

// TestFromSliceEqualsRepeatedAdd pins the O(n) construction against the O(n log
// n) one. They are different code paths writing the same array, and only this
// says so.
func TestFromSliceEqualsRepeatedAdd(t *testing.T) {
	vals := []int64{4, 0, 9, 2, 7, 1, 1, 6, 3}

	built := FromSlice(vals)
	added := New(len(vals))
	for i, v := range vals {
		added.Add(i, v)
	}

	uassert.Equal(t, len(built.t), len(added.t))
	for i := range built.t {
		uassert.Equal(t, built.t[i], added.t[i])
	}
}

func TestRange(t *testing.T) {
	vals := []int64{1, 2, 3, 4, 5}
	tr := FromSlice(vals)

	cases := []struct {
		name   string
		lo, hi int
		want   int64
	}{
		{"whole", 0, 5, 15},
		{"middle", 1, 4, 9},
		{"single", 2, 3, 3},
		{"empty", 2, 2, 0},
		{"inverted", 4, 1, 0},
		{"low clamped", -100, 2, 3},
		{"high clamped", 3, 100, 9},
		{"both clamped", -7, 700, 15},
		{"wholly below", -9, -2, 0},
		{"wholly above", 60, 90, 0},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			uassert.Equal(t, tc.want, tr.Range(tc.lo, tc.hi))
		})
	}
}

// TestReadsAreTotal is the package's load-bearing safety claim: no read panics,
// whatever it is handed. A realm renders with these, a live realm cannot be
// redeployed, so a panicking read is a permanently broken page.
func TestReadsAreTotal(t *testing.T) {
	for _, n := range []int{0, 1, 5} {
		tr := New(n)
		for i := 0; i < n; i++ {
			tr.Add(i, int64(i+1))
		}
		for _, i := range []int{-1 << 30, -1, 0, n, n + 1, 1 << 30} {
			tr.Prefix(i)
			tr.At(i)
			tr.Range(i, i+1)
			tr.Covers(i)
			tr.SearchPrefix(int64(i))
		}
		tr.Total()
		tr.Slice()
	}
}

func TestAtOutOfRangeIsZero(t *testing.T) {
	tr := FromSlice([]int64{1, 2, 3})
	uassert.Equal(t, int64(0), tr.At(-1))
	uassert.Equal(t, int64(0), tr.At(3))
	uassert.Equal(t, int64(0), tr.At(1<<20))
}

func TestPrefixClampsRatherThanPanics(t *testing.T) {
	tr := FromSlice([]int64{1, 2, 3})
	uassert.Equal(t, int64(0), tr.Prefix(-5))
	uassert.Equal(t, int64(6), tr.Prefix(99))
}

func TestAddAndSet(t *testing.T) {
	tr := FromSlice([]int64{1, 2, 3, 4})

	tr.Add(1, 10)
	uassert.Equal(t, int64(12), tr.At(1))
	uassert.Equal(t, int64(20), tr.Total())

	old := tr.Set(1, 2)
	uassert.Equal(t, int64(12), old)
	uassert.Equal(t, int64(2), tr.At(1))
	uassert.Equal(t, int64(10), tr.Total())

	tr.Add(3, -4)
	uassert.Equal(t, int64(0), tr.At(3))
	uassert.Equal(t, int64(6), tr.Total())
}

// TestWritesArePanicking is the other half of the read/write asymmetry. A
// write is a transaction and should abort; a read is a render and must not.
func TestWritesArePanicking(cur realm, t *testing.T) {
	tr := New(3)
	uassert.PanicsWithMessage(t, cur, "fenwick: index out of range", func() { tr.Add(3, 1) })
	uassert.PanicsWithMessage(t, cur, "fenwick: index out of range", func() { tr.Add(-1, 1) })
	uassert.PanicsWithMessage(t, cur, "fenwick: index out of range", func() { tr.Set(9, 1) })
	uassert.PanicsWithMessage(t, cur, "fenwick: negative size", func() { New(-1) })
	uassert.PanicsWithMessage(t, cur, "fenwick: size above MaxSize", func() { New(MaxSize + 1) })
	uassert.NotPanics(t, cur, func() { New(MaxSize) })
}

func TestSearchPrefixMatchesNaive(t *testing.T) {
	cases := []struct {
		name string
		vals []int64
	}{
		{"empty", []int64{}},
		{"flat", []int64{1, 1, 1, 1}},
		// Zero weights must be unselectable: this is the property a weighted
		// draw depends on, and the one a naive scan gets wrong by returning the
		// first index whose running total is merely >= target.
		{"with zeros", []int64{0, 3, 0, 0, 2, 0}},
		{"uneven", []int64{5, 0, 1, 9, 2}},
		{"leading zero", []int64{0, 0, 7}},
		{"eight", []int64{1, 2, 3, 4, 5, 6, 7, 8}},
		{"nine", []int64{9, 1, 1, 1, 1, 1, 1, 1, 1}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			tr := FromSlice(tc.vals)
			ref := naive(tc.vals)
			total := ref.prefix(len(tc.vals))
			// Probe every reachable target plus both sides of the boundary.
			for target := int64(-2); target <= total+2; target++ {
				uassert.Equal(t, ref.searchPrefix(target), tr.SearchPrefix(target))
			}
		})
	}
}

// TestSearchPrefixNeverSelectsAZeroWeight states the draw property directly,
// rather than leaving it implied by agreement with the reference.
func TestSearchPrefixNeverSelectsAZeroWeight(t *testing.T) {
	vals := []int64{0, 5, 0, 0, 3, 0, 2, 0}
	tr := FromSlice(vals)
	for target := int64(0); target < tr.Total(); target++ {
		got := tr.SearchPrefix(target)
		if vals[got] == 0 {
			t.Errorf("target %d selected slot %d, which has weight 0", target, got)
		}
	}
	// Every draw lands inside the tree, and only an exhausted target runs off
	// the end.
	uassert.Equal(t, tr.Len(), tr.SearchPrefix(tr.Total()))
}

// TestSearchPrefixIsProportional checks the distribution, not just the bounds:
// slot i must own exactly vals[i] of the Total targets.
func TestSearchPrefixIsProportional(t *testing.T) {
	vals := []int64{3, 1, 0, 6, 2}
	tr := FromSlice(vals)
	hits := make([]int64, len(vals))
	for target := int64(0); target < tr.Total(); target++ {
		hits[tr.SearchPrefix(target)]++
	}
	for i := range vals {
		uassert.Equal(t, vals[i], hits[i])
	}
}

func TestSlice(t *testing.T) {
	vals := []int64{6, 0, -2, 11}
	tr := FromSlice(vals)
	got := tr.Slice()
	uassert.Equal(t, len(vals), len(got))
	for i := range vals {
		uassert.Equal(t, vals[i], got[i])
	}
	uassert.Equal(t, 0, len(New(0).Slice()))
}

// TestFromSliceCopies pins that the tree does not alias the caller's slice.
func TestFromSliceCopies(t *testing.T) {
	vals := []int64{1, 2, 3}
	tr := FromSlice(vals)
	vals[0] = 999
	uassert.Equal(t, int64(1), tr.At(0))
}

func TestCovers(t *testing.T) {
	tr := New(8)
	cases := []struct {
		name   string
		i      int
		lo, hi int
	}{
		{"odd covers one", 1, 0, 1},
		{"two covers two", 2, 0, 2},
		{"three covers one", 3, 2, 3},
		{"four covers four", 4, 0, 4},
		{"six covers two", 6, 4, 6},
		{"eight covers all", 8, 0, 8},
		{"below range", 0, 0, 0},
		{"above range", 9, 0, 0},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			lo, hi := tr.Covers(tc.i)
			uassert.Equal(t, tc.lo, lo)
			uassert.Equal(t, tc.hi, hi)
		})
	}
}

// TestCoversPartitions is the structural claim behind the whole package: the
// nodes a Prefix walk visits tile [0, i) exactly, with no gap and no overlap.
// If that ever stops holding, every sum is wrong and this says so in one place.
func TestCoversPartitions(t *testing.T) {
	const n = 13
	tr := New(n)
	for i := 1; i <= n; i++ {
		covered := make([]bool, n)
		for j := i; j > 0; j -= lowBit(j) {
			lo, hi := tr.Covers(j)
			for k := lo; k < hi; k++ {
				if covered[k] {
					t.Errorf("prefix %d: slot %d covered twice", i, k)
				}
				covered[k] = true
			}
		}
		for k := 0; k < n; k++ {
			if covered[k] != (k < i) {
				t.Errorf("prefix %d: slot %d covered=%t, want %t", i, k, covered[k], k < i)
			}
		}
	}
}

func TestLowBit(t *testing.T) {
	cases := []struct{ in, want int }{
		{1, 1}, {2, 2}, {3, 1}, {4, 4}, {6, 2}, {8, 8}, {12, 4}, {96, 32},
	}
	for _, tc := range cases {
		uassert.Equal(t, tc.want, lowBit(tc.in))
	}
}

func TestHighBit(t *testing.T) {
	cases := []struct{ in, want int }{
		{0, 0}, {1, 1}, {2, 2}, {3, 2}, {4, 4}, {7, 4}, {8, 8}, {9, 8}, {1000, 512},
	}
	for _, tc := range cases {
		uassert.Equal(t, tc.want, highBit(tc.in))
	}
}

// TestLargeTreeStaysConsistent exercises a size past the small hand-checked
// cases, where a wrong jump in SearchPrefix would still look plausible.
func TestLargeTreeStaysConsistent(t *testing.T) {
	const n = 500
	vals := make([]int64, n)
	// Deterministic, and deliberately not uniform: a constant weight hides a
	// SearchPrefix that is off by a slot.
	for i := range vals {
		vals[i] = int64((i*7919)%13) + 1
	}
	tr := FromSlice(vals)
	ref := naive(vals)

	uassert.Equal(t, ref.prefix(n), tr.Total())
	for _, i := range []int{0, 1, 63, 64, 65, 255, 256, 257, n - 1, n} {
		uassert.Equal(t, ref.prefix(i), tr.Prefix(i))
	}
	for _, target := range []int64{0, 1, 100, 1000, tr.Total() - 1, tr.Total()} {
		uassert.Equal(t, ref.searchPrefix(target), tr.SearchPrefix(target))
	}

	tr.Add(499, 1000)
	uassert.Equal(t, ref.prefix(n)+1000, tr.Total())
	uassert.Equal(t, vals[499]+1000, tr.At(499))
}
