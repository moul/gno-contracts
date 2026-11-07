package segmenttree

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// sample is the worked example used by most tests: eight slots, small enough
// to check every answer by hand.
var sample = []int64{3, 1, 4, 1, 5, 9, 2, 6}

// naiveQuery is the reference every range test is checked against: the obvious
// O(n) loop nobody would ship. A structure whose whole claim is "same answers,
// fewer steps" is only worth trusting when the same-answers half is pinned
// against something too simple to be wrong.
func naiveQuery(op Op, values []int64, lo, hi int) int64 {
	acc := op.Identity()
	for i := lo; i < hi; i++ {
		switch op {
		case Min:
			if values[i] < acc {
				acc = values[i]
			}
		case Max:
			if values[i] > acc {
				acc = values[i]
			}
		default:
			acc += values[i]
		}
	}
	return acc
}

func TestQueryMatchesNaiveEverywhere(t *testing.T) {
	for _, op := range []Op{Sum, Min, Max} {
		tr := New(op, sample)
		for lo := 0; lo <= len(sample); lo++ {
			for hi := lo; hi <= len(sample); hi++ {
				got, ok := tr.Query(lo, hi)
				if lo == hi {
					uassert.False(t, ok, "empty range must report not-ok")
					continue
				}
				uassert.True(t, ok, "in-range query must report ok")
				uassert.Equal(t, naiveQuery(op, sample, lo, hi), got)
			}
		}
	}
}

func TestQueryKnownAnswers(t *testing.T) {
	cases := []struct {
		name   string
		op     Op
		lo, hi int
		want   int64
	}{
		{"sum of all", Sum, 0, 8, 31},
		{"sum of head", Sum, 0, 3, 8},
		{"sum of tail", Sum, 5, 8, 17},
		{"sum of one", Sum, 4, 5, 5},
		{"min of all", Min, 0, 8, 1},
		{"min avoiding the ones", Min, 4, 8, 2},
		{"min of one", Min, 5, 6, 9},
		{"max of all", Max, 0, 8, 9},
		{"max of head", Max, 0, 3, 4},
		{"max of one", Max, 0, 1, 3},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			tr := New(tc.op, sample)
			got, ok := tr.Query(tc.lo, tc.hi)
			uassert.True(t, ok)
			uassert.Equal(t, tc.want, got)
		})
	}
}

func TestSetRebuildsTheAnswers(t *testing.T) {
	tr := NewMin(sample)
	before, _ := tr.Query(0, 8)
	uassert.Equal(t, int64(1), before)

	// Replacing both 1s has to move the minimum, which only happens if the
	// path from the leaf to the root was recomputed.
	uassert.True(t, tr.Set(1, 7))
	uassert.True(t, tr.Set(3, 7))
	after, _ := tr.Query(0, 8)
	uassert.Equal(t, int64(2), after)

	v, ok := tr.At(1)
	uassert.True(t, ok)
	uassert.Equal(t, int64(7), v)
}

func TestAddIsSetPlusDelta(t *testing.T) {
	tr := NewSum(sample)
	uassert.True(t, tr.Add(0, 10))
	v, _ := tr.At(0)
	uassert.Equal(t, int64(13), v)
	total, _ := tr.Total()
	uassert.Equal(t, int64(41), total)
}

func TestOutOfRangeIsReportedNeverPanicked(t *testing.T) {
	tr := NewSum(sample)
	cases := []struct {
		name   string
		lo, hi int
	}{
		{"reversed", 5, 2},
		{"negative low", -1, 3},
		{"high past the end", 0, 99},
		{"both past the end", 9, 12},
		{"empty at the end", 8, 8},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, ok := tr.Query(tc.lo, tc.hi)
			uassert.False(t, ok)
			uassert.Equal(t, Sum.Identity(), got)
		})
	}

	_, ok := tr.At(-1)
	uassert.False(t, ok)
	_, ok = tr.At(8)
	uassert.False(t, ok)
	uassert.False(t, tr.Set(-1, 0))
	uassert.False(t, tr.Set(8, 0))
	uassert.False(t, tr.Add(99, 1))
}

func TestEmptyTree(t *testing.T) {
	tr := NewSum(nil)
	uassert.Equal(t, 0, tr.Len())
	uassert.Equal(t, 0, tr.Depth())
	uassert.Equal(t, 0, len(tr.Nodes()))
	uassert.Equal(t, 0, len(tr.Values()))

	got, ok := tr.Query(0, 0)
	uassert.False(t, ok)
	uassert.Equal(t, int64(0), got)

	got, ok = tr.Total()
	uassert.False(t, ok)
	uassert.Equal(t, int64(0), got)
}

func TestSingleElement(t *testing.T) {
	tr := NewMax([]int64{42})
	uassert.Equal(t, 1, tr.Len())
	uassert.Equal(t, 1, tr.Depth())
	got, ok := tr.Query(0, 1)
	uassert.True(t, ok)
	uassert.Equal(t, int64(42), got)
	uassert.True(t, tr.Set(0, -7))
	got, _ = tr.Total()
	uassert.Equal(t, int64(-7), got)
}

func TestIdentityAndString(t *testing.T) {
	uassert.Equal(t, int64(0), Sum.Identity())
	uassert.Equal(t, int64(9223372036854775807), Min.Identity())
	uassert.Equal(t, int64(-9223372036854775808), Max.Identity())
	uassert.Equal(t, "sum", Sum.String())
	uassert.Equal(t, "min", Min.String())
	uassert.Equal(t, "max", Max.String())
	uassert.Equal(t, "sum", Op(42).String())
}

func TestUnknownOpBehavesAsSum(t *testing.T) {
	tr := New(Op(42), sample)
	uassert.Equal(t, "sum", tr.Op().String())
	got, ok := tr.Query(0, 8)
	uassert.True(t, ok)
	uassert.Equal(t, int64(31), got)
}

func TestValuesIsACopy(t *testing.T) {
	tr := NewSum(sample)
	v := tr.Values()
	uassert.Equal(t, 8, len(v))
	v[0] = 1000
	got, _ := tr.At(0)
	uassert.Equal(t, int64(3), got, "mutating the returned slice must not reach the tree")

	// The constructor copies too: the caller's slice is not adopted.
	src := []int64{1, 2, 3}
	tr2 := NewSum(src)
	src[0] = 100
	total, _ := tr2.Total()
	uassert.Equal(t, int64(6), total)
}

func TestNodesCoverTheLeafRanges(t *testing.T) {
	// Five values padded to a width of eight, so the three padding leaves are
	// dropped and every remaining node still reports a clamped range.
	tr := NewSum([]int64{1, 2, 3, 4, 5})
	uassert.Equal(t, 4, tr.Depth())

	nodes := tr.Nodes()
	uassert.True(t, len(nodes) > 0)
	uassert.Equal(t, 0, nodes[0].Level, "the root comes first")
	uassert.Equal(t, 0, nodes[0].Lo)
	uassert.Equal(t, 5, nodes[0].Hi, "the root range is clamped to Len, not to the padded width")
	uassert.Equal(t, int64(15), nodes[0].Value)

	// Every node's value is the combine over the leaves it claims to cover,
	// and no node is pure padding.
	for _, n := range nodes {
		uassert.True(t, n.Lo < n.Hi)
		uassert.True(t, n.Hi <= tr.Len())
		uassert.Equal(t, naiveQuery(Sum, []int64{1, 2, 3, 4, 5}, n.Lo, n.Hi), n.Value)
	}

	// Breadth-first: levels never go backwards.
	for i := 1; i < len(nodes); i++ {
		uassert.True(t, nodes[i].Level >= nodes[i-1].Level)
	}
}

func TestPaddingIsNeutralForMinAndMax(t *testing.T) {
	// Three values pad to a width of four. Query stops at Len, so the padding
	// slot is never part of an answer and Total alone cannot see a wrong pad:
	// that assertion passes with the padding hardcoded to 0, which is how this
	// test was first written. What DOES fold the pad is a parent node, so the
	// root's value is the assertion that actually constrains the code.
	for _, tc := range []struct {
		op   Op
		want int64
	}{
		{Min, 4},
		{Max, 9},
	} {
		tr := New(tc.op, []int64{7, 9, 4})
		got, ok := tr.Total()
		uassert.True(t, ok)
		uassert.Equal(t, tc.want, got)

		root := tr.Nodes()[0]
		uassert.Equal(t, 0, root.Level)
		uassert.Equal(t, 0, root.Lo)
		uassert.Equal(t, 3, root.Hi, "the root range is clamped to Len")
		uassert.Equal(t, tc.want, root.Value, "a parent must not fold a non-identity pad")
	}
}
