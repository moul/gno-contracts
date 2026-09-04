package multiset

import (
	"strconv"
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestEmpty(t *testing.T) {
	m := New()
	uassert.True(t, m.IsEmpty())
	uassert.Equal(t, 0, m.Distinct())
	uassert.Equal(t, 0, m.Total())
	uassert.Equal(t, 0, m.Count("nope"))
	uassert.False(t, m.Has("nope"))
}

func TestAddAndCount(t *testing.T) {
	m := New()
	m.Add("apple")
	m.Add("apple")
	m.Add("pear")

	uassert.Equal(t, 2, m.Count("apple"))
	uassert.Equal(t, 1, m.Count("pear"))
	uassert.Equal(t, 2, m.Distinct(), "distinct counts elements, not occurrences")
	uassert.Equal(t, 3, m.Total(), "total counts occurrences")
	uassert.True(t, m.Has("apple"))
}

func TestAddN(t *testing.T) {
	m := New()
	uassert.True(t, m.AddN("x", 5))
	uassert.Equal(t, 5, m.Count("x"))

	uassert.True(t, m.AddN("x", 0), "adding zero is a no-op that succeeds")
	uassert.True(t, m.AddN("x", -3), "adding a negative is a no-op that succeeds")
	uassert.Equal(t, 5, m.Count("x"), "count unchanged by non-positive AddN")
	uassert.Equal(t, 5, m.Total())
}

func TestFromSlice(t *testing.T) {
	m := FromSlice([]string{"a", "b", "a", "c", "a"})
	uassert.Equal(t, 3, m.Count("a"))
	uassert.Equal(t, 1, m.Count("b"))
	uassert.Equal(t, 3, m.Distinct())
	uassert.Equal(t, 5, m.Total())
}

func TestRemove(t *testing.T) {
	m := FromSlice([]string{"a", "a", "a"})

	uassert.True(t, m.Remove("a"))
	uassert.Equal(t, 2, m.Count("a"))
	uassert.Equal(t, 2, m.Total())

	uassert.False(t, m.Remove("absent"), "removing an absent element reports false")
}

// TestRemoveDeletesAtZero pins that a count reaching zero drops the element
// rather than leaving a zero-count ghost that Distinct would still count.
func TestRemoveDeletesAtZero(t *testing.T) {
	m := New()
	m.Add("a")

	uassert.True(t, m.Remove("a"))
	uassert.Equal(t, 0, m.Distinct(), "a zero count removes the element entirely")
	uassert.False(t, m.Has("a"))
	uassert.Equal(t, 0, m.Total())
}

// TestRemoveNClamps pins that over-removing clears rather than going negative.
func TestRemoveNClamps(t *testing.T) {
	m := New()
	m.AddN("a", 3)

	uassert.True(t, m.RemoveN("a", 100))
	uassert.Equal(t, 0, m.Count("a"))
	uassert.Equal(t, 0, m.Total(), "total must not go negative")
	uassert.Equal(t, 0, m.Distinct())
}

func TestRemoveNPartial(t *testing.T) {
	m := New()
	m.AddN("a", 10)
	uassert.True(t, m.RemoveN("a", 4))
	uassert.Equal(t, 6, m.Count("a"))
	uassert.Equal(t, 6, m.Total())
	uassert.False(t, m.RemoveN("a", 0), "a non-positive n reports false")
}

func TestRemoveAll(t *testing.T) {
	m := New()
	m.AddN("a", 7)
	m.Add("b")

	uassert.True(t, m.RemoveAll("a"))
	uassert.Equal(t, 0, m.Count("a"))
	uassert.Equal(t, 1, m.Total(), "only b remains")
	uassert.False(t, m.RemoveAll("a"), "already gone")
}

func TestElementsSorted(t *testing.T) {
	m := FromSlice([]string{"delta", "alpha", "charlie", "alpha"})
	uassert.Equal(t, "alpha,charlie,delta", strings.Join(m.Elements(), ","))
}

func TestExpand(t *testing.T) {
	m := FromSlice([]string{"b", "a", "b"})
	uassert.Equal(t, "a,b,b", strings.Join(m.Expand(), ","))
	uassert.Equal(t, m.Total(), len(m.Expand()), "Expand length equals Total")
}

func TestMostCommon(t *testing.T) {
	m := FromSlice([]string{"a", "a", "a", "b", "b", "c"})

	top := m.MostCommon(2)
	uassert.Equal(t, 2, len(top))
	uassert.Equal(t, "a", top[0].Elem)
	uassert.Equal(t, 3, top[0].Count)
	uassert.Equal(t, "b", top[1].Elem)
	uassert.Equal(t, 2, top[1].Count)
}

// TestMostCommonTiesAreAlphabetical is the determinism guarantee: equal counts
// must not fall back on map order, which gno leaves unspecified.
func TestMostCommonTiesAreAlphabetical(t *testing.T) {
	m := FromSlice([]string{"zebra", "apple", "mango"}) // all count 1

	got := m.MostCommon(0)
	uassert.Equal(t, 3, len(got))
	uassert.Equal(t, "apple", got[0].Elem)
	uassert.Equal(t, "mango", got[1].Elem)
	uassert.Equal(t, "zebra", got[2].Elem)
}

// TestMostCommonIsStableAcrossBuilds is the same property from the outside:
// build the set twice, get the same ranking.
func TestMostCommonIsStableAcrossBuilds(t *testing.T) {
	build := func() *MultiSet {
		m := New()
		for i := 0; i < 60; i++ {
			m.Add("e" + strconv.Itoa(i%9))
		}
		return m
	}
	uassert.Equal(t, rank(build().MostCommon(0)), rank(build().MostCommon(0)))
}

func TestMostCommonBounds(t *testing.T) {
	m := FromSlice([]string{"a", "b"})
	uassert.Equal(t, 2, len(m.MostCommon(0)), "n<=0 returns everything")
	uassert.Equal(t, 2, len(m.MostCommon(-1)), "negative n returns everything")
	uassert.Equal(t, 2, len(m.MostCommon(99)), "n beyond distinct returns everything")
	uassert.Equal(t, 1, len(m.MostCommon(1)))
	uassert.Equal(t, 0, len(New().MostCommon(5)), "empty set ranks nothing")
}

func TestUnionTakesMaximum(t *testing.T) {
	a := FromSlice([]string{"x", "x", "y"})
	b := FromSlice([]string{"x", "z", "z", "z"})

	u := a.Union(b)
	uassert.Equal(t, 2, u.Count("x"), "max(2,1)")
	uassert.Equal(t, 1, u.Count("y"), "max(1,0)")
	uassert.Equal(t, 3, u.Count("z"), "max(0,3)")
	uassert.Equal(t, 6, u.Total())
	uassert.Equal(t, 3, a.Total(), "operands are untouched")
}

func TestIntersectTakesMinimum(t *testing.T) {
	a := FromSlice([]string{"x", "x", "x", "y"})
	b := FromSlice([]string{"x", "x", "z"})

	i := a.Intersect(b)
	uassert.Equal(t, 2, i.Count("x"), "min(3,2)")
	uassert.Equal(t, 0, i.Count("y"), "absent from b")
	uassert.Equal(t, 0, i.Count("z"), "absent from a")
	uassert.Equal(t, 1, i.Distinct())
	uassert.Equal(t, 2, i.Total())
}

func TestSumAddsCounts(t *testing.T) {
	a := FromSlice([]string{"x", "x", "y"})
	b := FromSlice([]string{"x", "z"})

	s := a.Sum(b)
	uassert.Equal(t, 3, s.Count("x"), "2+1")
	uassert.Equal(t, 1, s.Count("y"))
	uassert.Equal(t, 1, s.Count("z"))
	uassert.Equal(t, 5, s.Total())
}

func TestClone(t *testing.T) {
	m := FromSlice([]string{"a", "a"})
	cp := m.Clone()
	cp.Add("b")

	uassert.Equal(t, 1, m.Distinct(), "clone must not share storage")
	uassert.Equal(t, 2, cp.Distinct())
	uassert.Equal(t, 2, m.Total())
	uassert.Equal(t, 3, cp.Total())
}

func TestMaxDistinct(t *testing.T) {
	m := New()
	for i := 0; i < MaxDistinct; i++ {
		uassert.True(t, m.Add("e"+strconv.Itoa(i)), "should accept up to MaxDistinct")
	}
	uassert.Equal(t, MaxDistinct, m.Distinct())

	uassert.False(t, m.Add("overflow"), "a full set refuses a new distinct element")
	uassert.Equal(t, MaxDistinct, m.Distinct())

	// Counts are NOT bounded: an existing element can still grow.
	uassert.True(t, m.AddN("e0", 1000), "existing elements still accept occurrences")
	uassert.Equal(t, 1001, m.Count("e0"))
}

func rank(es []Entry) string {
	parts := make([]string, len(es))
	for i, e := range es {
		parts[i] = e.Elem + ":" + strconv.Itoa(e.Count)
	}
	return strings.Join(parts, ",")
}
