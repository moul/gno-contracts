// Package intervalset is a set of half-open integer ranges kept sorted,
// disjoint and coalesced, as a pure, reusable package.
//
// Realms keep ranges constantly: vesting windows, auction and sale periods,
// booking slots, block-height gates, allowlisted id ranges. The obvious
// implementation is a slice of pairs appended to on every write, and it is
// wrong in three ways that only show up later. It grows with the number of
// WRITES rather than with the shape of the data, so a realm that accepts a
// thousand overlapping windows stores a thousand of them forever. Asking
// whether a point is covered becomes a linear scan that gets slower with every
// one. And adding up the covered length double-counts every overlap, which is
// the bug that makes such a list wrong for billing.
//
// This type keeps one invariant instead, after every single operation: the
// spans are sorted ascending, non-empty, and separated by a real gap. Two
// ranges that overlap OR merely touch become one span, so [0,5) and [5,10) are
// stored as [0,10). The count is therefore a property of the data and can only
// shrink when ranges are added.
//
// Ranges are HALF-OPEN: [Lo, Hi) contains Lo and excludes Hi. That is what lets
// touching ranges merge without overlapping, and it is the detail callers get
// wrong. An empty or inverted range (Hi <= Lo) is a no-op on Add and Remove
// rather than a panic, because a realm usually computes both ends from data.
//
// Add, Remove and Measure are O(n) in the number of spans; Contains, Covers and
// Overlaps are O(log n) by binary search, and those are the ones a Render calls.
//
// A live demo of this package is at
// [r/moul/x/daily/intervalsetdemo](/r/moul/x/daily/intervalsetdemo/v0).
package intervalset

// MaxSpans bounds the set so gas stays predictable. Only an Add that would
// create a new span is refused; one that merges into an existing span is always
// allowed, because it cannot grow the count.
const MaxSpans = 1024

// Span is the half-open range [Lo, Hi). Hi is never covered.
type Span struct {
	Lo int64
	Hi int64
}

// Set is a set of integers stored as sorted, disjoint, coalesced spans.
// The zero value is not usable: call New.
type Set struct {
	spans []Span
}

// New returns an empty Set.
func New() *Set { return &Set{} }

// Len returns the number of spans, not the number of integers covered. It only
// ever shrinks when ranges are added, which is the point of coalescing.
func (s *Set) Len() int { return len(s.spans) }

// Measure returns the total number of integers covered, counting an overlap
// once. The invariant is what makes this a plain sum.
func (s *Set) Measure() int64 {
	var total int64
	for _, sp := range s.spans {
		total += sp.Hi - sp.Lo
	}
	return total
}

// Spans returns the spans in ascending order, as an independent copy.
func (s *Set) Spans() []Span {
	out := make([]Span, len(s.spans))
	copy(out, s.spans)
	return out
}

// Clone returns an independent copy.
func (s *Set) Clone() *Set {
	return &Set{spans: s.Spans()}
}

// Clear empties the set.
func (s *Set) Clear() { s.spans = nil }

// Add covers [lo, hi), merging with every span it overlaps or touches.
//
// It returns false, changing nothing, only when the set is already at MaxSpans
// and the range would add a span rather than merge into one. An empty or
// inverted range is a no-op and reports true: nothing was refused.
func (s *Set) Add(lo, hi int64) bool {
	if hi <= lo {
		return true
	}
	// Everything ending before lo stays untouched. "Ending before lo" is
	// sp.Hi < lo and not <=, so a span that merely touches is merged.
	i := 0
	for i < len(s.spans) && s.spans[i].Hi < lo {
		i++
	}
	// Everything starting after hi stays untouched, same reasoning.
	j := i
	for j < len(s.spans) && s.spans[j].Lo <= hi {
		j++
	}
	if i == j && len(s.spans) >= MaxSpans {
		return false // a brand new span, and there is no room for one
	}
	if j > i {
		if s.spans[i].Lo < lo {
			lo = s.spans[i].Lo
		}
		if s.spans[j-1].Hi > hi {
			hi = s.spans[j-1].Hi
		}
	}
	s.spans = replace(s.spans, i, j, []Span{{Lo: lo, Hi: hi}})
	return true
}

// Remove uncovers [lo, hi). A range removed from the middle of a span splits
// it in two, which is the only operation here that can raise the span count.
func (s *Set) Remove(lo, hi int64) {
	if hi <= lo {
		return
	}
	// Strict inequalities both ways: a span merely touching the removed range
	// shares no integer with it and must be left alone.
	i := 0
	for i < len(s.spans) && s.spans[i].Hi <= lo {
		i++
	}
	j := i
	for j < len(s.spans) && s.spans[j].Lo < hi {
		j++
	}
	if i == j {
		return
	}
	kept := []Span{}
	if s.spans[i].Lo < lo {
		kept = append(kept, Span{Lo: s.spans[i].Lo, Hi: lo})
	}
	if s.spans[j-1].Hi > hi {
		kept = append(kept, Span{Lo: hi, Hi: s.spans[j-1].Hi})
	}
	s.spans = replace(s.spans, i, j, kept)
}

// Contains reports whether v is covered. O(log n).
func (s *Set) Contains(v int64) bool {
	i := s.search(v)
	return i < len(s.spans) && s.spans[i].Lo <= v && v < s.spans[i].Hi
}

// Covers reports whether every integer in [lo, hi) is covered, by a SINGLE
// span: the invariant guarantees a gap between spans, so a range crossing one
// is not covered. An empty range is covered by anything, including the empty
// set.
func (s *Set) Covers(lo, hi int64) bool {
	if hi <= lo {
		return true
	}
	i := s.search(lo)
	return i < len(s.spans) && s.spans[i].Lo <= lo && hi <= s.spans[i].Hi
}

// Overlaps reports whether [lo, hi) shares at least one integer with the set.
// An empty range overlaps nothing.
func (s *Set) Overlaps(lo, hi int64) bool {
	if hi <= lo {
		return false
	}
	i := s.search(lo)
	return i < len(s.spans) && s.spans[i].Lo < hi
}

// String renders the set as "[0,5) [10,20)", empty as "". Useful in a test
// assertion and in a Render alike.
func (s *Set) String() string {
	out := ""
	for i, sp := range s.spans {
		if i > 0 {
			out += " "
		}
		out += "[" + itoa(sp.Lo) + "," + itoa(sp.Hi) + ")"
	}
	return out
}

// search returns the index of the first span whose Hi is strictly greater than
// v, which is the only span that can contain v. len(spans) when there is none.
func (s *Set) search(v int64) int {
	lo, hi := 0, len(s.spans)
	for lo < hi {
		mid := int(uint(lo+hi) >> 1)
		if s.spans[mid].Hi <= v {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	return lo
}

// replace swaps spans[i:j] for with, in one allocation. Written out because
// the slice-of-slices append idiom aliases its first argument, and getting that
// wrong here corrupts the invariant silently rather than failing.
func replace(spans []Span, i, j int, with []Span) []Span {
	out := make([]Span, 0, len(spans)-(j-i)+len(with))
	out = append(out, spans[:i]...)
	out = append(out, with...)
	out = append(out, spans[j:]...)
	return out
}

// itoa formats an int64 without reaching for strconv, so the package stays
// import-free.
func itoa(v int64) string {
	if v == 0 {
		return "0"
	}
	neg := v < 0
	if neg {
		v = -v
	}
	buf := [20]byte{}
	i := len(buf)
	for v > 0 {
		i--
		buf[i] = byte('0' + v%10)
		v /= 10
	}
	if neg {
		i--
		buf[i] = '-'
	}
	return string(buf[i:])
}
