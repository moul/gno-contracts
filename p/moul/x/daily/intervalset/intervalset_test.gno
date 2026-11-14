package intervalset

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// add applies a script of "lo-hi" adds and "!lo-hi" removes, so a scenario
// reads as the story it is rather than ten statements.
func run(s *Set, script []string) {
	for _, op := range script {
		rm := strings.HasPrefix(op, "!")
		if rm {
			op = op[1:]
		}
		i := strings.Index(op, ":")
		lo := atoi(op[:i])
		hi := atoi(op[i+1:])
		if rm {
			s.Remove(lo, hi)
		} else {
			s.Add(lo, hi)
		}
	}
}

func atoi(s string) int64 {
	neg := false
	if strings.HasPrefix(s, "-") {
		neg, s = true, s[1:]
	}
	var n int64
	for _, c := range s {
		n = n*10 + int64(c-'0')
	}
	if neg {
		return -n
	}
	return n
}

func TestAddAndString(t *testing.T) {
	s := New()
	uassert.Equal(t, 0, s.Len())
	uassert.Equal(t, "", s.String())
	uassert.Equal(t, int64(0), s.Measure())

	s.Add(10, 20)
	s.Add(0, 5)
	uassert.Equal(t, "[0,5) [10,20)", s.String()) // kept sorted, not insertion order
	uassert.Equal(t, 2, s.Len())
	uassert.Equal(t, int64(15), s.Measure())
}

// An empty or inverted range is a no-op, not a panic and not a zero-length
// span: a caller computing lo and hi from data should not have to pre-check.
func TestEmptyRangeIsANoop(t *testing.T) {
	s := New()
	s.Add(5, 5)
	s.Add(9, 3)
	uassert.Equal(t, 0, s.Len())
	s.Add(0, 10)
	s.Remove(4, 4)
	s.Remove(8, 2)
	uassert.Equal(t, "[0,10)", s.String())
}

// Coalescing is the invariant the whole type exists to keep: touching spans
// become one, so the count tracks the SHAPE of the data and not the number of
// writes.
func TestAddCoalesces(t *testing.T) {
	tests := []struct {
		name   string
		script []string
		want   string
	}{
		{"disjoint stay apart", []string{"0:5", "10:15"}, "[0,5) [10,15)"},
		{"adjacent merge", []string{"0:5", "5:10"}, "[0,10)"},
		{"adjacent merge, reversed", []string{"5:10", "0:5"}, "[0,10)"},
		{"overlapping merge", []string{"0:7", "5:12"}, "[0,12)"},
		{"contained is absorbed", []string{"0:20", "5:10"}, "[0,20)"},
		{"containing absorbs", []string{"5:10", "0:20"}, "[0,20)"},
		{"bridges a gap", []string{"0:5", "10:15", "4:11"}, "[0,15)"},
		{"bridges three", []string{"0:2", "4:6", "8:10", "1:9"}, "[0,10)"},
		{"same span twice", []string{"3:8", "3:8"}, "[3,8)"},
		{"negative values", []string{"-10:-5", "-5:0"}, "[-10,0)"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			s := New()
			run(s, tt.script)
			uassert.Equal(t, tt.want, s.String())
		})
	}
}

func TestRemove(t *testing.T) {
	tests := []struct {
		name   string
		script []string
		want   string
	}{
		{"hole in the middle splits", []string{"0:10", "!4:6"}, "[0,4) [6,10)"},
		{"trim the front", []string{"0:10", "!0:3"}, "[3,10)"},
		{"trim the back", []string{"0:10", "!7:10"}, "[0,7)"},
		{"remove everything", []string{"0:10", "!0:10"}, ""},
		{"wider than the span", []string{"2:8", "!0:20"}, ""},
		{"across several spans", []string{"0:5", "10:15", "20:25", "!3:22"}, "[0,3) [22,25)"},
		{"misses entirely", []string{"0:5", "!10:15"}, "[0,5)"},
		{"touching but not overlapping", []string{"0:5", "!5:10"}, "[0,5)"},
		{"touching from the other side", []string{"5:10", "!0:5"}, "[5,10)"},
		{"re-adding closes the hole", []string{"0:10", "!4:6", "4:6"}, "[0,10)"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			s := New()
			run(s, tt.script)
			uassert.Equal(t, tt.want, s.String())
		})
	}
}

// Half-open means Hi is NOT covered. That is the whole reason adjacent spans
// may merge without overlapping, and it is the detail callers get wrong.
func TestContainsIsHalfOpen(t *testing.T) {
	s := New()
	s.Add(10, 20)
	uassert.False(t, s.Contains(9))
	uassert.True(t, s.Contains(10)) // Lo is in
	uassert.True(t, s.Contains(19))
	uassert.False(t, s.Contains(20)) // Hi is out
	uassert.False(t, s.Contains(21))
}

func TestContainsAcrossManySpans(t *testing.T) {
	s := New()
	for i := int64(0); i < 20; i++ {
		s.Add(i*10, i*10+5)
	}
	uassert.Equal(t, 20, s.Len())
	uassert.True(t, s.Contains(0))
	uassert.True(t, s.Contains(104))
	uassert.False(t, s.Contains(105))
	uassert.True(t, s.Contains(194))
	uassert.False(t, s.Contains(195)) // [190,195) excludes its Hi
	uassert.False(t, s.Contains(199))
	uassert.False(t, s.Contains(-1))
	uassert.False(t, s.Contains(1000))
}

func TestCoversAndOverlaps(t *testing.T) {
	s := New()
	s.Add(0, 5)
	s.Add(10, 20)

	uassert.True(t, s.Covers(0, 5))
	uassert.True(t, s.Covers(11, 19))
	uassert.False(t, s.Covers(0, 6))   // runs past the end of the span
	uassert.False(t, s.Covers(3, 12))  // crosses the gap
	uassert.True(t, s.Covers(7, 7))    // an empty range is covered by anything
	uassert.False(t, s.Covers(99, 100))

	uassert.True(t, s.Overlaps(3, 12)) // crossing the gap still touches both
	uassert.True(t, s.Overlaps(-5, 1))
	uassert.False(t, s.Overlaps(5, 10)) // exactly the gap
	uassert.False(t, s.Overlaps(7, 7))  // an empty range overlaps nothing
}

func TestSpansIsACopy(t *testing.T) {
	s := New()
	s.Add(0, 5)
	sp := s.Spans()
	uassert.Equal(t, 1, len(sp))
	uassert.Equal(t, int64(0), sp[0].Lo)
	uassert.Equal(t, int64(5), sp[0].Hi)

	sp[0].Lo = 999
	uassert.Equal(t, "[0,5)", s.String())
}

func TestCloneIsIndependent(t *testing.T) {
	s := New()
	s.Add(0, 10)
	c := s.Clone()
	c.Remove(2, 4)
	uassert.Equal(t, "[0,10)", s.String())
	uassert.Equal(t, "[0,2) [4,10)", c.String())
}

func TestClear(t *testing.T) {
	s := New()
	s.Add(0, 10)
	s.Clear()
	uassert.Equal(t, 0, s.Len())
	uassert.Equal(t, int64(0), s.Measure())
	s.Add(1, 2)
	uassert.Equal(t, "[1,2)", s.String())
}

// MaxSpans bounds growth. Add refuses rather than panicking, because the
// caller of a bounded set is usually a realm handling user input.
func TestMaxSpans(cur realm, t *testing.T) {
	s := New()
	for i := int64(0); i < MaxSpans; i++ {
		uassert.True(t, s.Add(i*2, i*2+1))
	}
	uassert.Equal(t, MaxSpans, s.Len())
	uassert.False(t, s.Add(100000, 100001)) // would be one span too many

	// A span that MERGES is always allowed: the count does not grow.
	uassert.True(t, s.Add(0, 1))
	uassert.True(t, s.Add(1, 2))
	uassert.Equal(t, MaxSpans-1, s.Len())
}

// Measure is the covered length, and double-counting it is the bug that makes
// a hand-rolled list of windows wrong for billing.
func TestMeasureDoesNotDoubleCount(t *testing.T) {
	s := New()
	s.Add(0, 10)
	s.Add(5, 15) // overlaps by 5
	uassert.Equal(t, int64(15), s.Measure())
	uassert.Equal(t, 1, s.Len())

	s.Remove(3, 6)
	uassert.Equal(t, int64(12), s.Measure())
}
