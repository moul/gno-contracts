package store

import (
	"strconv"
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestZeroValueIsUsable(t *testing.T) {
	var s Store
	uassert.Equal(t, 0, s.Len())
	uassert.Equal(t, uint64(0), uint64(s.LastID()))
	uassert.Equal(t, uint64(1), uint64(s.Add("first")))
	uassert.Equal(t, 1, s.Len())
}

func TestAddAssignsSequentialIDsFromOne(t *testing.T) {
	s := New()
	for want := uint64(1); want <= 5; want++ {
		uassert.Equal(t, want, uint64(s.Add("v"+strconv.FormatUint(want, 10))))
	}
	uassert.Equal(t, 5, s.Len())
	uassert.Equal(t, uint64(5), uint64(s.LastID()))
}

func TestGetHasMustGet(t *testing.T) {
	s := New()
	id := s.Add("hello")

	got, ok := s.Get(id)
	uassert.True(t, ok, "live id is found")
	uassert.Equal(t, "hello", got.(string))
	uassert.True(t, s.Has(id), "Has agrees with Get")
	uassert.Equal(t, "hello", s.MustGet(id).(string))

	_, ok = s.Get(ID(2))
	uassert.False(t, ok, "unassigned id misses")
	_, ok = s.Get(ID(0))
	uassert.False(t, ok, "the zero id always misses")
	uassert.False(t, s.Has(ID(0)), "the zero id is never present")
}

// A nil value at a live id must still read as present. avl.Tree.Get alone
// cannot tell those apart, which is why Get consults Has.
func TestNilValueIsDistinguishableFromAbsent(t *testing.T) {
	s := New()
	id := s.Add(nil)

	v, ok := s.Get(id)
	uassert.True(t, ok, "a stored nil is present")
	uassert.Nil(t, v, "and reads back as nil")
	uassert.Equal(t, 1, s.Len())
}

func TestMustGetPanicsNamingTheEntry(cur realm, t *testing.T) {
	s := New()
	s.Add("only")
	uassert.PanicsWithMessage(t, cur, "store: no entry #7", func() { s.MustGet(ID(7)) })
	uassert.NotPanics(t, cur, func() { s.MustGet(ID(1)) })
}

// A labelled store keeps the realm's own wording, so porting one does not
// trade "game not found" for a generic message.
func TestNamedStoreUsesItsLabelInThePanic(cur realm, t *testing.T) {
	s := Named("game")
	s.Add("only")
	uassert.PanicsWithMessage(t, cur, "game #7 not found", func() { s.MustGet(ID(7)) })
	uassert.NotPanics(t, cur, func() { s.MustGet(ID(1)) })

	// The label changes nothing else.
	uassert.Equal(t, uint64(1), uint64(s.LastID()))
	uassert.Equal(t, 1, s.Len())
}

func TestSetReplacesInPlace(t *testing.T) {
	s := New()
	id := s.Add("before")

	uassert.True(t, s.Set(id, "after"), "Set reports the replacement")
	uassert.Equal(t, "after", s.MustGet(id).(string))
	uassert.Equal(t, 1, s.Len(), "replacing does not grow the store")
	uassert.Equal(t, uint64(1), uint64(s.LastID()), "replacing does not move the counter")
}

func TestRemoveDoesNotRecycleIDs(t *testing.T) {
	s := New()
	a := s.Add("a")
	s.Add("b")

	v, ok := s.Remove(a)
	uassert.True(t, ok, "removing a live id succeeds")
	uassert.Equal(t, "a", v.(string))
	uassert.Equal(t, 1, s.Len())

	_, ok = s.Remove(a)
	uassert.False(t, ok, "removing twice is a miss, not a panic")

	// The next Add continues the history rather than refilling the hole.
	uassert.Equal(t, uint64(3), uint64(s.Add("c")))
}

func TestParseID(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want ID
		ok   bool
	}{
		{"plain", "7", 7, true},
		{"leading zeros", "007", 7, true},
		{"max uint64", "18446744073709551615", ID(18446744073709551615), true},
		{"empty", "", 0, false},
		{"zero is never assigned", "0", 0, false},
		{"negative", "-1", 0, false},
		{"signed positive", "+1", 0, false},
		{"decimal point", "1.0", 0, false},
		{"not a number", "abc", 0, false},
		{"trailing space", "7 ", 0, false},
		{"overflows uint64", "18446744073709551616", 0, false},
	}
	for _, tc := range cases {
		got, ok := ParseID(tc.in)
		uassert.Equal(t, tc.ok, ok, tc.name+": ok")
		uassert.Equal(t, uint64(tc.want), uint64(got), tc.name+": value")
	}
}

// The round trip a realm actually performs: render an id into a path, take it
// back off the path, look the entry up.
func TestIDRoundTripsThroughAPath(t *testing.T) {
	s := New()
	id := s.Add("entry")
	for i := 0; i < 20; i++ {
		id = s.Add("entry")
	}

	parsed, ok := ParseID(id.String())
	uassert.True(t, ok, "the rendered id parses back")
	uassert.Equal(t, uint64(id), uint64(parsed))
	uassert.Equal(t, "entry", s.MustGet(parsed).(string))
}

func TestKeyIsFixedWidthAndOrdered(t *testing.T) {
	uassert.Equal(t, 8, len(ID(1).Key()), "every key is 8 bytes")
	uassert.Equal(t, 8, len(ID(18446744073709551615).Key()), "including the largest")

	// Byte order is numeric order, which is the whole point.
	prev := ID(0).Key()
	for _, n := range []uint64{1, 9, 10, 99, 100, 999999, 1000000, 999999999999, 1000000000000, 18446744073709551615} {
		k := ID(n).Key()
		uassert.True(t, prev < k, "keys ascend at "+strconv.FormatUint(n, 10))
		prev = k
	}
}

// padWidth is the shape sixteen realm files carry, reproduced so the defect it
// causes is asserted rather than described. The widths in the tree are 6
// (asciiart), 12 (most) and 16 (guestbook).
func padWidth(n uint64, width int) string {
	s := strconv.FormatUint(n, 10)
	if len(s) >= width {
		return s
	}
	return strings.Repeat("0", width-len(s)) + s
}

// The ceiling: one entry past the chosen width, decimal keys stop sorting
// numerically. store's keys do not have a width to outgrow.
func TestOrderSurvivesThePaddingCeiling(t *testing.T) {
	cases := []struct {
		name   string
		width  int
		lo, hi uint64
	}{
		{"asciiart, width 6", 6, 999999, 1000000},
		{"the width 12 majority", 12, 999999999999, 1000000000000},
		{"guestbook, width 16", 16, 9999999999999999, 10000000000000000},
	}
	for _, tc := range cases {
		// The hand-rolled key inverts: the larger id sorts first.
		uassert.True(t, padWidth(tc.hi, tc.width) < padWidth(tc.lo, tc.width),
			tc.name+": the padded key is expected to invert here")

		// The store key does not.
		uassert.True(t, ID(tc.lo).Key() < ID(tc.hi).Key(), tc.name+": store keys stay ordered")

		// And iteration follows.
		s := New()
		s.Set(ID(tc.hi), "hi")
		s.Set(ID(tc.lo), "lo")
		var order []string
		s.Each(func(id ID, v any) { order = append(order, v.(string)) })
		uassert.Equal(t, "lo,hi", strings.Join(order, ","), tc.name+": iteration is numeric")
	}
}

// timecapsule's variant calls strings.Repeat without the len guard, so past
// the width it panics instead of mis-sorting: the realm stops accepting
// writes. Asserted here because it is the reason this is a correctness fix and
// not a tidy-up.
func TestUnguardedPadPanicsPastItsWidth(cur realm, t *testing.T) {
	unguarded := func(n uint64) string {
		return strings.Repeat("0", 12-len(strconv.FormatUint(n, 10))) + strconv.FormatUint(n, 10)
	}
	uassert.NotPanics(t, cur, func() { unguarded(999999999999) })
	uassert.PanicsContains(t, cur, "negative", func() { unguarded(1000000000000) })
	uassert.NotPanics(t, cur, func() { ID(1000000000000).Key() })
}

func TestEachVisitsEverythingInOrder(t *testing.T) {
	s := New()
	for i := 1; i <= 5; i++ {
		s.Add(strconv.Itoa(i))
	}

	var fwd, rev []string
	s.Each(func(id ID, v any) { fwd = append(fwd, id.String()+"="+v.(string)) })
	s.EachReverse(func(id ID, v any) { rev = append(rev, id.String()+"="+v.(string)) })

	uassert.Equal(t, "1=1,2=2,3=3,4=4,5=5", strings.Join(fwd, ","))
	uassert.Equal(t, "5=5,4=4,3=3,2=2,1=1", strings.Join(rev, ","))
}

func TestEachOnAnEmptyStoreIsANoOp(t *testing.T) {
	s := New()
	calls := 0
	s.Each(func(id ID, v any) { calls++ })
	s.EachReverse(func(id ID, v any) { calls++ })
	uassert.Equal(t, 0, calls)
	uassert.Equal(t, 0, len(s.Page(1, 10)))
	uassert.Equal(t, 0, s.Pages(10))
}

// True means stop, the same as avl.IterCbFn, so a callback keeps its meaning
// when it moves between this package and a raw tree.
func TestEachUntilStopsOnTrue(t *testing.T) {
	s := New()
	for i := 1; i <= 5; i++ {
		s.Add(strconv.Itoa(i))
	}

	var seen []string
	stopped := s.EachUntil(func(id ID, v any) bool {
		seen = append(seen, v.(string))
		return id == 3
	})
	uassert.True(t, stopped, "it reports stopping early")
	uassert.Equal(t, "1,2,3", strings.Join(seen, ","))

	seen = nil
	stopped = s.EachReverseUntil(func(id ID, v any) bool {
		seen = append(seen, v.(string))
		return id == 4
	})
	uassert.True(t, stopped)
	uassert.Equal(t, "5,4", strings.Join(seen, ","))

	stopped = s.EachUntil(func(id ID, v any) bool { return false })
	uassert.False(t, stopped, "running to the end is not stopping early")
}

func TestPageIsOneBased(t *testing.T) {
	s := New()
	for i := 1; i <= 7; i++ {
		s.Add(strconv.Itoa(i))
	}

	cases := []struct {
		name       string
		page, size int
		want       string
	}{
		{"first page", 1, 3, "1,2,3"},
		{"second page", 2, 3, "4,5,6"},
		{"short last page", 3, 3, "7"},
		{"past the end", 4, 3, ""},
		{"far past the end", 99, 3, ""},
		{"whole store in one page", 1, 100, "1,2,3,4,5,6,7"},
		{"page 0 is not page 1", 0, 3, ""},
		{"negative page", -1, 3, ""},
		{"size 0", 1, 0, ""},
		{"negative size", 1, -3, ""},
	}
	for _, tc := range cases {
		var got []string
		for _, e := range s.Page(tc.page, tc.size) {
			got = append(got, e.Value.(string))
		}
		uassert.Equal(t, tc.want, strings.Join(got, ","), tc.name)
	}
}

func TestPageReverseStartsWithTheNewest(t *testing.T) {
	s := New()
	for i := 1; i <= 7; i++ {
		s.Add(strconv.Itoa(i))
	}

	cases := []struct {
		name       string
		page, size int
		want       string
	}{
		{"newest first", 1, 3, "7,6,5"},
		{"second page", 2, 3, "4,3,2"},
		{"short last page", 3, 3, "1"},
		{"past the end", 4, 3, ""},
	}
	for _, tc := range cases {
		var got []string
		for _, e := range s.PageReverse(tc.page, tc.size) {
			got = append(got, e.Value.(string))
		}
		uassert.Equal(t, tc.want, strings.Join(got, ","), tc.name)
	}
}

func TestPageCarriesTheID(t *testing.T) {
	s := New()
	s.Add("a")
	s.Add("b")

	p := s.Page(1, 10)
	uassert.Equal(t, 2, len(p))
	uassert.Equal(t, uint64(1), uint64(p[0].ID))
	uassert.Equal(t, uint64(2), uint64(p[1].ID))

	r := s.PageReverse(1, 10)
	uassert.Equal(t, uint64(2), uint64(r[0].ID))
	uassert.Equal(t, uint64(1), uint64(r[1].ID))
}

func TestPages(t *testing.T) {
	s := New()
	uassert.Equal(t, 0, s.Pages(10), "an empty store has no pages")

	for i := 1; i <= 10; i++ {
		s.Add("v")
	}
	uassert.Equal(t, 1, s.Pages(10), "an exact fit is one page")
	uassert.Equal(t, 2, s.Pages(9), "a remainder adds a page")
	uassert.Equal(t, 10, s.Pages(1))
	uassert.Equal(t, 0, s.Pages(0), "a size below 1 has no pages")
	uassert.Equal(t, 0, s.Pages(-1))
}

// Paging and iteration must stay consistent after entries are removed from the
// middle, which is where a dense-index assumption would break.
func TestPagingAfterRemovals(t *testing.T) {
	s := New()
	for i := 1; i <= 6; i++ {
		s.Add(strconv.Itoa(i))
	}
	s.Remove(ID(2))
	s.Remove(ID(5))

	uassert.Equal(t, 4, s.Len())
	uassert.Equal(t, uint64(6), uint64(s.LastID()), "the counter does not rewind")

	var got []string
	s.Each(func(id ID, v any) { got = append(got, id.String()) })
	uassert.Equal(t, "1,3,4,6", strings.Join(got, ","))

	got = nil
	for _, e := range s.Page(2, 2) {
		got = append(got, e.ID.String())
	}
	uassert.Equal(t, "4,6", strings.Join(got, ","), "page 2 of the survivors")
	uassert.Equal(t, 2, s.Pages(2))
}
