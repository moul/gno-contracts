package hyperloglog

import (
	"strconv"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// fill adds n synthetic elements numbered from first. The elements are
// generated, never random: every number in this file is reproducible by
// running the test again, which is the only way a statistical package can be
// tested at all.
func fill(s *Sketch, prefix string, first, n int) {
	for i := first; i < first+n; i++ {
		s.Add(prefix + strconv.Itoa(i))
	}
}

// abs64 is local rather than imported: the dependency would exist for three
// lines used only by tests.
func abs64(v int64) int64 {
	if v < 0 {
		return -v
	}
	return v
}

func TestEmptySketch(t *testing.T) {
	s := NewDefault()
	uassert.Equal(t, int64(0), s.Count(), "an empty sketch counts nothing")
	uassert.Equal(t, 1024, s.Registers())
	uassert.Equal(t, 1024, s.Zeros(), "every register starts at zero")
	uassert.Equal(t, int64(0), s.Adds())
	uassert.Equal(t, DefaultPrecision, s.Precision())
}

func TestNewRejectsPrecisionOutOfRange(t *testing.T) {
	for _, p := range []int{-1, 0, 3, 17, 64} {
		s, err := New(p)
		uassert.ErrorIs(t, err, ErrBadPrecision, "precision "+strconv.Itoa(p))
		// TypedNil, not Nil: a nil *Sketch handed to an any parameter is a
		// typed nil, and uassert.Nil reports it as non-nil.
		uassert.TypedNil(t, s)
	}
	for _, p := range []int{MinPrecision, 10, MaxPrecision} {
		s, err := New(p)
		uassert.NoError(t, err, "precision "+strconv.Itoa(p))
		uassert.Equal(t, 1<<uint(p), s.Registers())
	}
}

// TestDuplicatesCountOnce is the whole point of the structure: the same
// element arriving a thousand times moves no register after the first.
func TestDuplicatesCountOnce(t *testing.T) {
	s := NewDefault()
	for i := 0; i < 1000; i++ {
		s.Add("the-same-caller")
	}
	uassert.Equal(t, int64(1), s.Count(), "one distinct element")
	uassert.Equal(t, int64(1000), s.Adds(), "a thousand calls")
	uassert.Equal(t, 1023, s.Zeros(), "exactly one register was touched")
}

// TestSmallRangeIsExact pins the linear-counting branch. Below a few hundred
// elements at p=14 the odds of two of them landing on the same register are
// negligible, so the count is not an estimate at all: it is the number of
// registers that moved, corrected for a collision that did not happen.
func TestSmallRangeIsExact(t *testing.T) {
	for _, n := range []int{0, 1, 2, 3, 5, 8, 13, 21} {
		s, err := New(14)
		uassert.NoError(t, err)
		fill(s, "u", 0, n)
		uassert.Equal(t, int64(n), s.Count(), "exact at n="+strconv.Itoa(n))
	}
}

// TestWithinErrorBound checks the estimate against the theoretical standard
// error, 1.04/sqrt(m). Four sigma is the bound: a correct implementation
// clears it on essentially every input, and the arithmetic mistakes that
// matter (a wrong alpha, a missing square, a sum built the wrong way round)
// miss it by multiples rather than by a little.
func TestWithinErrorBound(t *testing.T) {
	for _, n := range []int{200, 1000, 5000, 10000} {
		s := NewDefault()
		fill(s, "user-", 0, n)
		got := s.Count()
		bound := int64(4 * s.RelativeError() * float64(n))
		if bound < 2 {
			bound = 2
		}
		off := abs64(got - int64(n))
		uassert.True(t, off <= bound,
			"n="+strconv.Itoa(n)+" estimate="+strconv.FormatInt(got, 10)+
				" off by "+strconv.FormatInt(off, 10)+", bound "+strconv.FormatInt(bound, 10))
	}
}

// TestCountNeverDecreases pins monotonicity. The estimator is not a counter,
// so nothing in its arithmetic guarantees this on its own: it holds because a
// register only ever moves up.
func TestCountNeverDecreases(t *testing.T) {
	s := NewDefault()
	prev := int64(0)
	for i := 0; i < 4000; i++ {
		s.Add("e" + strconv.Itoa(i))
		if i%250 != 0 {
			continue
		}
		got := s.Count()
		uassert.True(t, got >= prev,
			"count fell from "+strconv.FormatInt(prev, 10)+" to "+strconv.FormatInt(got, 10))
		prev = got
	}
}

// TestOrderIndependent is an exact test of a statistical structure: the
// registers are a maximum, and a maximum does not care in which order it was
// shown its inputs. Two sketches fed the same elements forwards and backwards
// must be byte-identical, not merely close.
func TestOrderIndependent(t *testing.T) {
	forward := NewDefault()
	backward := NewDefault()
	for i := 0; i < 500; i++ {
		forward.Add("x" + strconv.Itoa(i))
	}
	for i := 499; i >= 0; i-- {
		backward.Add("x" + strconv.Itoa(i))
	}
	a, b := forward.Snapshot(), backward.Snapshot()
	uassert.Equal(t, len(a), len(b))
	for i := range a {
		uassert.Equal(t, a[i], b[i], "register "+strconv.Itoa(i))
	}
	uassert.Equal(t, forward.Count(), backward.Count())
}

// TestMergeCountsTheUnion is the property an exact counter cannot offer: two
// shards counted apart, combined afterwards, with the overlap counted once.
func TestMergeCountsTheUnion(t *testing.T) {
	left := NewDefault()
	right := NewDefault()
	fill(left, "k", 0, 1000)   // k0 .. k999
	fill(right, "k", 500, 1000) // k500 .. k1499, overlapping by 500

	uassert.NoError(t, left.Merge(right))

	const union = 1500
	bound := int64(4 * left.RelativeError() * union)
	off := abs64(left.Count() - union)
	uassert.True(t, off <= bound,
		"union estimate "+strconv.FormatInt(left.Count(), 10)+" off by "+strconv.FormatInt(off, 10))
}

// TestMergeIsIdempotent: merging a sketch with itself must change nothing,
// which is what makes a merge safe to replay.
func TestMergeIsIdempotent(t *testing.T) {
	s := NewDefault()
	fill(s, "z", 0, 300)
	before := s.Snapshot()

	uassert.NoError(t, s.Merge(s.Clone()))

	after := s.Snapshot()
	for i := range before {
		uassert.Equal(t, before[i], after[i], "register "+strconv.Itoa(i))
	}
}

func TestMergeRejectsOtherPrecisions(t *testing.T) {
	a, err := New(10)
	uassert.NoError(t, err)
	b, err := New(11)
	uassert.NoError(t, err)
	uassert.ErrorIs(t, a.Merge(b), ErrPrecisionMismatch)
	uassert.ErrorIs(t, a.Merge(nil), ErrNilSketch)
}

func TestSnapshotRoundTrip(t *testing.T) {
	s := NewDefault()
	fill(s, "r", 0, 750)

	restored, err := FromSnapshot(s.Precision(), s.Snapshot())
	uassert.NoError(t, err)
	uassert.Equal(t, s.Count(), restored.Count())
	uassert.Equal(t, s.Zeros(), restored.Zeros())
	uassert.Equal(t, int64(0), restored.Adds(), "a restored sketch has seen no calls of its own")

	_, err = FromSnapshot(10, []uint8{1, 2, 3})
	uassert.ErrorIs(t, err, ErrBadSnapshot, "a snapshot of the wrong length")
	_, err = FromSnapshot(3, nil)
	uassert.ErrorIs(t, err, ErrBadPrecision)
}

// TestSnapshotIsACopy: a caller that stores a snapshot must not be holding
// the live registers, or the stored copy would keep changing underneath it.
func TestSnapshotIsACopy(t *testing.T) {
	s := NewDefault()
	s.Add("one")
	snap := s.Snapshot()
	fill(s, "more", 0, 100)
	restored, err := FromSnapshot(s.Precision(), snap)
	uassert.NoError(t, err)
	uassert.Equal(t, int64(1), restored.Count(), "the snapshot froze at one element")
}

// TestCloneIsIndependent compares the clone against an independently built
// sketch rather than against the literal 100, because at p=10 a hundred
// elements land on about ninety registers and linear counting corrects for
// the collisions statistically, not exactly. Asserting the round number here
// would be asserting that the estimator is a counter, which it is not.
func TestCloneIsIndependent(t *testing.T) {
	s := NewDefault()
	fill(s, "c", 0, 100)
	reference := NewDefault()
	fill(reference, "c", 0, 100)

	c := s.Clone()
	fill(s, "c", 100, 400)

	uassert.Equal(t, reference.Count(), c.Count(), "the clone did not see the later adds")
	uassert.Equal(t, int64(100), c.Adds())
	uassert.True(t, s.Count() > c.Count()+300, "the original did see them")
}

func TestReset(t *testing.T) {
	s := NewDefault()
	fill(s, "q", 0, 200)
	s.Reset()
	uassert.Equal(t, int64(0), s.Count())
	uassert.Equal(t, int64(0), s.Adds())
	uassert.Equal(t, s.Registers(), s.Zeros())
}

// TestFootprintIsFixed is the claim the package is sold on: the memory is a
// function of the precision alone, and a million elements do not add a byte.
func TestFootprintIsFixed(t *testing.T) {
	s := NewDefault()
	before := s.Bytes()
	fill(s, "big", 0, 20000)
	uassert.Equal(t, before, s.Bytes(), "20k elements, same footprint")
	uassert.Equal(t, 1024, s.Bytes(), "one byte per register at p=10")

	wide, err := New(16)
	uassert.NoError(t, err)
	uassert.Equal(t, 65536, wide.Bytes())
}

func TestRelativeErrorShrinksWithPrecision(t *testing.T) {
	tests := []struct {
		precision int
		maxErr    float64
	}{
		{4, 0.27},
		{10, 0.033},
		{14, 0.009},
		{16, 0.005},
	}
	prev := 1.0
	for _, tt := range tests {
		s, err := New(tt.precision)
		uassert.NoError(t, err)
		got := s.RelativeError()
		uassert.True(t, got <= tt.maxErr,
			"p="+strconv.Itoa(tt.precision)+" relative error too large")
		uassert.True(t, got < prev, "error must fall as precision rises")
		prev = got
	}
}

// TestAddAll is the batch form, and it must agree with the loop exactly.
func TestAddAll(t *testing.T) {
	loop := NewDefault()
	batch := NewDefault()
	items := []string{"a", "b", "c", "b", "a"}
	for _, it := range items {
		loop.Add(it)
	}
	batch.AddAll(items)
	uassert.Equal(t, loop.Count(), batch.Count())
	uassert.Equal(t, loop.Adds(), batch.Adds())
	uassert.Equal(t, int64(3), batch.Count())
}

// TestEmptyStringIsAnElement: "" is a value a caller can legitimately hold,
// so it is counted rather than ignored. Silently dropping it would make the
// count disagree with the caller's own set by one, which is the kind of bug
// an estimate hides.
func TestEmptyStringIsAnElement(t *testing.T) {
	s := NewDefault()
	s.Add("")
	uassert.Equal(t, int64(1), s.Count())
	s.Add("")
	uassert.Equal(t, int64(1), s.Count())
}

// TestHashSpreadsAcrossRegisters guards the hash rather than the estimator. A
// broken hash still produces a plausible-looking small count, so the estimate
// tests above would not catch one: this asserts that a thousand elements
// actually landed in many hundreds of different registers.
func TestHashSpreadsAcrossRegisters(t *testing.T) {
	s := NewDefault()
	fill(s, "spread", 0, 1000)
	touched := s.Registers() - s.Zeros()
	uassert.True(t, touched > 600,
		"only "+strconv.Itoa(touched)+" of 1024 registers were touched")
}
