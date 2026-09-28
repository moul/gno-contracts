package tally

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func keys(entries []Entry) string {
	out := ""
	for i, e := range entries {
		if i > 0 {
			out += ","
		}
		out += e.Key
	}
	return out
}

func TestSortOrdersByScoreThenKey(t *testing.T) {
	cases := []struct {
		name string
		in   []Entry
		want string
	}{
		{"already ordered", []Entry{{"a", 3}, {"b", 2}, {"c", 1}}, "a,b,c"},
		{"reversed", []Entry{{"c", 1}, {"b", 2}, {"a", 3}}, "a,b,c"},
		{"all tied, key decides", []Entry{{"c", 5}, {"a", 5}, {"b", 5}}, "a,b,c"},
		{"partial tie", []Entry{{"z", 1}, {"b", 9}, {"a", 9}}, "a,b,z"},
		{"negatives sort below", []Entry{{"a", -1}, {"b", 0}, {"c", 1}}, "c,b,a"},
		{"single", []Entry{{"only", 7}}, "only"},
		{"empty", nil, ""},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			in := make([]Entry, len(tc.in))
			copy(in, tc.in)
			Sort(in)
			uassert.Equal(t, tc.want, keys(in))
		})
	}
}

// TestSortIsATotalOrder is the defect this package exists to remove. A
// comparator whose last clause repeats the score (rpgroom's third clause) is
// not a total order: two equal rows compare false both ways and their order is
// decided by the algorithm. Sorting twice from different inputs must agree.
func TestSortIsATotalOrder(t *testing.T) {
	a := []Entry{{"x", 5}, {"y", 5}, {"z", 5}, {"w", 9}}
	b := []Entry{{"z", 5}, {"w", 9}, {"y", 5}, {"x", 5}}
	Sort(a)
	Sort(b)
	uassert.Equal(t, keys(a), keys(b))
	uassert.Equal(t, "w,x,y,z", keys(a))
}

func TestTop(t *testing.T) {
	in := []Entry{{"c", 1}, {"a", 3}, {"b", 2}}
	uassert.Equal(t, "a,b", keys(Top(in, 2)))
	uassert.Equal(t, "a,b,c", keys(Top(in, 10)))
	uassert.Equal(t, "", keys(Top(in, 0)))
	uassert.Equal(t, "", keys(Top(in, -1)))
	uassert.Equal(t, "", keys(Top(nil, 3)))
}

// TestTopDoesNotDisturbTheCaller pins that Top copies. A realm that renders a
// Top(3) and then iterates its own slice must not find it reordered.
func TestTopDoesNotDisturbTheCaller(t *testing.T) {
	in := []Entry{{"c", 1}, {"a", 3}, {"b", 2}}
	_ = Top(in, 2)
	uassert.Equal(t, "c,a,b", keys(in))
}

func TestRank(t *testing.T) {
	in := []Entry{{"c", 1}, {"a", 3}, {"b", 2}}
	uassert.Equal(t, 1, Rank(in, "a"))
	uassert.Equal(t, 2, Rank(in, "b"))
	uassert.Equal(t, 3, Rank(in, "c"))
	uassert.Equal(t, 0, Rank(in, "absent"))
}

// TestRankNeverTies is what makes a rendered "#3" mean something: two equal
// scores still get 2 and 3, never 2 and 2.
func TestRankNeverTies(t *testing.T) {
	in := []Entry{{"a", 5}, {"b", 5}, {"c", 5}}
	seen := map[int]bool{}
	for _, e := range in {
		r := Rank(in, e.Key)
		if seen[r] {
			t.Errorf("rank %d claimed twice", r)
		}
		seen[r] = true
	}
	uassert.Equal(t, 3, len(seen))
}

func TestBoardAddAndScore(t *testing.T) {
	b := NewBoard()
	uassert.Equal(t, 0, b.Len())
	uassert.Equal(t, int64(5), b.Add("a", 5))
	uassert.Equal(t, int64(8), b.Add("a", 3))
	uassert.Equal(t, int64(6), b.Add("a", -2))
	uassert.Equal(t, int64(6), b.Score("a"))
	uassert.Equal(t, int64(0), b.Score("never"))
	uassert.Equal(t, 1, b.Len())
}

func TestBoardHasDistinguishesAbsentFromZero(t *testing.T) {
	b := NewBoard()
	b.Set("zero", 0)
	uassert.True(t, b.Has("zero"))
	uassert.False(t, b.Has("absent"))
	uassert.Equal(t, int64(0), b.Score("zero"))
	uassert.Equal(t, int64(0), b.Score("absent"))
}

func TestBoardRemove(t *testing.T) {
	b := NewBoard()
	b.Set("a", 1)
	uassert.True(t, b.Remove("a"))
	uassert.False(t, b.Remove("a"))
	uassert.Equal(t, 0, b.Len())
}

func TestBoardEntriesAndTop(t *testing.T) {
	b := NewBoard()
	b.Set("c", 1)
	b.Set("a", 3)
	b.Set("b", 3)
	uassert.Equal(t, "a,b,c", keys(b.Entries()))
	uassert.Equal(t, "a,b", keys(b.Top(2)))
	uassert.Equal(t, 1, b.Rank("a"))
	uassert.Equal(t, 2, b.Rank("b"))
	uassert.Equal(t, 0, b.Rank("absent"))
}

// TestBoardOrderDoesNotDependOnInsertion is the reason Board is backed by a
// tree and not a map: the same scores inserted in a different order must
// render identically.
func TestBoardOrderDoesNotDependOnInsertion(t *testing.T) {
	one := NewBoard()
	for _, e := range []Entry{{"a", 5}, {"b", 5}, {"c", 9}} {
		one.Set(e.Key, e.Score)
	}
	two := NewBoard()
	for _, e := range []Entry{{"c", 9}, {"b", 5}, {"a", 5}} {
		two.Set(e.Key, e.Score)
	}
	uassert.Equal(t, keys(one.Entries()), keys(two.Entries()))
	uassert.Equal(t, "c,a,b", keys(one.Entries()))
}
