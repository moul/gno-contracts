package countminsketch

import (
	"strconv"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestNewValidation(t *testing.T) {
	_, err := New(MinWidth-1, 4)
	uassert.ErrorIs(t, err, ErrBadWidth)
	_, err = New(MaxWidth+1, 4)
	uassert.ErrorIs(t, err, ErrBadWidth)
	_, err = New(256, MinDepth-1)
	uassert.ErrorIs(t, err, ErrBadDepth)
	_, err = New(256, MaxDepth+1)
	uassert.ErrorIs(t, err, ErrBadDepth)

	_, err = New(MinWidth, MinDepth)
	uassert.NoError(t, err, "the minimum dimensions are valid")
	_, err = New(MaxWidth, MaxDepth)
	uassert.NoError(t, err, "the maximum dimensions are valid")
}

func TestDimensions(t *testing.T) {
	s, _ := New(64, 3)
	uassert.Equal(t, 64, s.Width())
	uassert.Equal(t, 3, s.Depth())
	uassert.Equal(t, 192, s.Counters(), "storage is width*depth, fixed")

	d := NewDefault()
	uassert.Equal(t, 256, d.Width())
	uassert.Equal(t, 4, d.Depth())
}

func TestEmptyEstimatesZero(t *testing.T) {
	s := NewDefault()
	uassert.Equal(t, int64(0), s.Estimate("anything"))
	uassert.False(t, s.MightHave("anything"))
	uassert.Equal(t, int64(0), s.Total())
}

func TestAddAndEstimate(t *testing.T) {
	s := NewDefault()
	for i := 0; i < 5; i++ {
		s.Add("apple")
	}
	s.Add("pear")

	uassert.Equal(t, int64(5), s.Estimate("apple"))
	uassert.Equal(t, int64(1), s.Estimate("pear"))
	uassert.Equal(t, int64(6), s.Total())
	uassert.True(t, s.MightHave("apple"))
}

func TestAddNRejectsNonPositive(t *testing.T) {
	s := NewDefault()
	uassert.ErrorIs(t, s.AddN("x", 0), ErrBadCount)
	uassert.ErrorIs(t, s.AddN("x", -3), ErrBadCount)
	uassert.Equal(t, int64(0), s.Total(), "a rejected add changes nothing")
}

func TestAddNAccumulates(t *testing.T) {
	s := NewDefault()
	uassert.NoError(t, s.AddN("x", 100))
	uassert.NoError(t, s.AddN("x", 50))
	uassert.Equal(t, int64(150), s.Estimate("x"))
	uassert.Equal(t, int64(150), s.Total())
}

// TestNeverUndercounts is THE contract. A tiny sketch guarantees collisions;
// the estimate must still never fall below the truth.
func TestNeverUndercounts(t *testing.T) {
	s, _ := New(MinWidth, 2) // deliberately tiny: 4 columns, collisions certain

	truth := map[string]int64{}
	for i := 0; i < 300; i++ {
		e := "e" + strconv.Itoa(i%40)
		s.Add(e)
		truth[e]++
	}

	for e, want := range truth {
		got := s.Estimate(e)
		uassert.True(t, got >= want,
			"estimate must never undercount "+e+": got "+strconv.FormatInt(got, 10)+
				" want >= "+strconv.FormatInt(want, 10))
	}
}

// TestExactWhenNoCollisions checks a generously sized sketch is exact for a
// handful of elements — the common case.
func TestExactWhenNoCollisions(t *testing.T) {
	s, _ := New(MaxWidth, 4)
	s.AddN("alpha", 7)
	s.AddN("bravo", 3)
	s.AddN("charlie", 11)

	uassert.Equal(t, int64(7), s.Estimate("alpha"))
	uassert.Equal(t, int64(3), s.Estimate("bravo"))
	uassert.Equal(t, int64(11), s.Estimate("charlie"))
}

// TestAbsentIsDefinitiveWhenZero pins the useful direction of the one-sided
// error: zero means definitely never added.
func TestAbsentIsDefinitiveWhenZero(t *testing.T) {
	s, _ := New(MaxWidth, 4)
	s.Add("present")
	uassert.False(t, s.MightHave("definitely-absent"), "a zero estimate is definitive")
}

// TestEstimateBoundedByTotal pins the other side: an estimate can never exceed
// everything that was ever added.
func TestEstimateBoundedByTotal(t *testing.T) {
	s, _ := New(MinWidth, 1)
	for i := 0; i < 100; i++ {
		s.Add("e" + strconv.Itoa(i))
	}
	for i := 0; i < 100; i++ {
		uassert.True(t, s.Estimate("e"+strconv.Itoa(i)) <= s.Total(),
			"no estimate may exceed the total")
	}
}

// TestDeterministicAcrossInstances is what makes this safe on chain: the same
// input yields the same counters everywhere, with no map-order dependence.
func TestDeterministicAcrossInstances(t *testing.T) {
	build := func() *Sketch {
		s, _ := New(32, 3)
		for i := 0; i < 200; i++ {
			s.Add("elem" + strconv.Itoa(i%25))
		}
		return s
	}
	a, b := build(), build()

	for r := 0; r < a.Depth(); r++ {
		ra, rb := a.Row(r), b.Row(r)
		for c := range ra {
			uassert.Equal(t, ra[c], rb[c], "counters must match across instances")
		}
	}
	uassert.Equal(t, a.Estimate("elem7"), b.Estimate("elem7"))
}

func TestIndexIsStableAndInRange(t *testing.T) {
	s, _ := New(64, 3)
	for r := 0; r < 3; r++ {
		i := s.Index("hello", r)
		uassert.True(t, i >= 0 && i < 64, "index must be within the row")
		uassert.Equal(t, i, s.Index("hello", r), "index must be stable")
	}
	uassert.Equal(t, -1, s.Index("hello", -1), "out-of-range row")
	uassert.Equal(t, -1, s.Index("hello", 3))
}

// TestRowsHashIndependently checks the per-row seed actually changes the column,
// which is what makes taking the minimum meaningful.
func TestRowsHashIndependently(t *testing.T) {
	s, _ := New(MaxWidth, MaxDepth)
	first := s.Index("some-element", 0)
	differs := false
	for r := 1; r < s.Depth(); r++ {
		if s.Index("some-element", r) != first {
			differs = true
		}
	}
	uassert.True(t, differs, "rows must not all map to the same column")
}

func TestMerge(t *testing.T) {
	a, _ := New(128, 3)
	b, _ := New(128, 3)
	a.AddN("x", 5)
	b.AddN("x", 7)
	b.AddN("y", 2)

	uassert.NoError(t, a.Merge(b))
	uassert.Equal(t, int64(12), a.Estimate("x"), "merged counts add")
	uassert.Equal(t, int64(2), a.Estimate("y"))
	uassert.Equal(t, int64(14), a.Total())
}

func TestMergeRejectsMismatchedShape(t *testing.T) {
	a, _ := New(128, 3)
	uassert.ErrorIs(t, a.Merge(mustNew(t, 64, 3)), ErrBadWidth)
	uassert.ErrorIs(t, a.Merge(mustNew(t, 128, 2)), ErrBadDepth)
	uassert.Equal(t, int64(0), a.Total(), "a rejected merge changes nothing")
}

func TestReset(t *testing.T) {
	s := NewDefault()
	s.AddN("x", 10)
	s.Reset()

	uassert.Equal(t, int64(0), s.Estimate("x"))
	uassert.Equal(t, int64(0), s.Total())
	uassert.Equal(t, 256, s.Width(), "dimensions survive a reset")
}

func TestClone(t *testing.T) {
	s := NewDefault()
	s.AddN("x", 4)

	cp := s.Clone()
	cp.AddN("x", 6)

	uassert.Equal(t, int64(4), s.Estimate("x"), "clone must not share storage")
	uassert.Equal(t, int64(10), cp.Estimate("x"))
	uassert.Equal(t, s.Width(), cp.Width())
}

func TestRowCopy(t *testing.T) {
	s, _ := New(8, 2)
	s.Add("x")

	row := s.Row(0)
	uassert.Equal(t, 8, len(row))
	row[0] = 999
	uassert.False(t, s.Row(0)[0] == 999, "Row returns a copy")

	uassert.True(t, s.Row(-1) == nil)
	uassert.True(t, s.Row(2) == nil)
}

func mustNew(t *testing.T, w, d int) *Sketch {
	s, err := New(w, d)
	uassert.NoError(t, err)
	return s
}
