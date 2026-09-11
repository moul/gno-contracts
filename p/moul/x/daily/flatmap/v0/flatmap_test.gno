package flatmap

import (
	"strconv"
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestEmpty(t *testing.T) {
	f := New()
	uassert.Equal(t, 0, f.Len())
	uassert.True(t, f.IsEmpty())
	uassert.False(t, f.Has("a"))
	uassert.True(t, f.Sorted(), "an empty map is trivially sorted")

	_, ok := f.Get("a")
	uassert.False(t, ok)
	_, _, ok = f.At(0)
	uassert.False(t, ok)
}

// TestStaysSortedRegardlessOfInsertionOrder is the core invariant.
func TestStaysSortedRegardlessOfInsertionOrder(t *testing.T) {
	f := New()
	for _, k := range []string{"delta", "alpha", "echo", "bravo", "charlie"} {
		f.Set(k, "v-"+k)
	}
	uassert.Equal(t, "alpha,bravo,charlie,delta,echo", strings.Join(f.Keys(), ","))
	uassert.True(t, f.Sorted())
}

func TestGetSet(t *testing.T) {
	f := New()
	uassert.True(t, f.Set("b", "2"))
	uassert.True(t, f.Set("a", "1"))

	v, ok := f.Get("a")
	uassert.True(t, ok)
	uassert.Equal(t, "1", v)

	_, ok = f.Get("zzz")
	uassert.False(t, ok)
}

func TestSetUpdatesInPlace(t *testing.T) {
	f := New()
	f.Set("a", "1")
	f.Set("b", "2")

	uassert.True(t, f.Set("a", "99"))
	uassert.Equal(t, 2, f.Len(), "updating must not add an entry")

	v, _ := f.Get("a")
	uassert.Equal(t, "99", v)
	uassert.True(t, f.Sorted())
}

func TestValuesFollowKeyOrder(t *testing.T) {
	f := New()
	f.Set("c", "3")
	f.Set("a", "1")
	f.Set("b", "2")
	uassert.Equal(t, "1,2,3", strings.Join(f.Values(), ","))
}

func TestDelete(t *testing.T) {
	f := New()
	for _, k := range []string{"a", "b", "c", "d"} {
		f.Set(k, k)
	}

	uassert.True(t, f.Delete("b"))
	uassert.Equal(t, "a,c,d", strings.Join(f.Keys(), ","), "the gap must close")
	uassert.Equal(t, "a,c,d", strings.Join(f.Values(), ","), "values shift with keys")
	uassert.Equal(t, 3, f.Len())
	uassert.True(t, f.Sorted())

	uassert.False(t, f.Delete("b"), "deleting twice reports false")
}

func TestDeleteEnds(t *testing.T) {
	f := New()
	for _, k := range []string{"a", "b", "c"} {
		f.Set(k, k)
	}
	uassert.True(t, f.Delete("a"))
	uassert.True(t, f.Delete("c"))
	uassert.Equal(t, "b", strings.Join(f.Keys(), ","))
	uassert.True(t, f.Delete("b"))
	uassert.True(t, f.IsEmpty())
}

func TestAt(t *testing.T) {
	f := New()
	f.Set("b", "2")
	f.Set("a", "1")

	k, v, ok := f.At(0)
	uassert.True(t, ok)
	uassert.Equal(t, "a", k)
	uassert.Equal(t, "1", v)

	_, _, ok = f.At(-1)
	uassert.False(t, ok)
	_, _, ok = f.At(2)
	uassert.False(t, ok)
}

func TestIterateAndStop(t *testing.T) {
	f := New()
	for _, k := range []string{"c", "a", "b"} {
		f.Set(k, strings.ToUpper(k))
	}

	var seen []string
	f.Iterate(func(k, v string) bool {
		seen = append(seen, k+"="+v)
		return false
	})
	uassert.Equal(t, "a=A,b=B,c=C", strings.Join(seen, ","))

	count := 0
	f.Iterate(func(k, v string) bool { count++; return true })
	uassert.Equal(t, 1, count, "returning true stops iteration")
}

// TestRange is the query sorted storage makes cheap.
func TestRange(t *testing.T) {
	f := New()
	for _, k := range []string{"a", "b", "c", "d", "e"} {
		f.Set(k, k)
	}

	uassert.Equal(t, "b,c,d", collect(f, "b", "e"), "lo inclusive, hi exclusive")
	uassert.Equal(t, "c,d,e", collect(f, "c", ""), "empty hi runs to the end")
	uassert.Equal(t, "a,b,c,d,e", collect(f, "", ""), "empty bounds cover everything")
	uassert.Equal(t, "", collect(f, "x", "z"), "a range past the end yields nothing")
	uassert.Equal(t, "", collect(f, "c", "c"), "an empty half-open range yields nothing")
}

func TestRangeStops(t *testing.T) {
	f := New()
	for _, k := range []string{"a", "b", "c"} {
		f.Set(k, k)
	}
	n := 0
	f.Range("", "", func(k, v string) bool { n++; return true })
	uassert.Equal(t, 1, n)
}

func TestRangeOnAbsentBoundary(t *testing.T) {
	f := New()
	for _, k := range []string{"a", "c", "e"} {
		f.Set(k, k)
	}
	// "b" and "d" are not present; the range still lands correctly.
	uassert.Equal(t, "c", collect(f, "b", "d"))
}

func TestKeysAndValuesAreCopies(t *testing.T) {
	f := New()
	f.Set("a", "1")
	f.Set("b", "2")

	ks := f.Keys()
	ks[0] = "mutated"
	vs := f.Values()
	vs[0] = "mutated"

	uassert.Equal(t, "a,b", strings.Join(f.Keys(), ","), "callers cannot reorder the map through Keys")
	uassert.Equal(t, "1,2", strings.Join(f.Values(), ","))
}

func TestClone(t *testing.T) {
	f := New()
	f.Set("a", "1")

	cp := f.Clone()
	cp.Set("b", "2")

	uassert.Equal(t, 1, f.Len(), "clone must not share storage")
	uassert.Equal(t, 2, cp.Len())
	uassert.True(t, cp.Sorted())
}

func TestMaxEntries(t *testing.T) {
	f := New()
	for i := 0; i < MaxEntries; i++ {
		uassert.True(t, f.Set(pad(i), "v"), "should accept up to MaxEntries")
	}
	uassert.Equal(t, MaxEntries, f.Len())

	uassert.False(t, f.Set("zzz-overflow", "v"), "a full map refuses a new key")
	uassert.Equal(t, MaxEntries, f.Len())

	uassert.True(t, f.Set(pad(0), "updated"), "a full map still accepts updates")
	v, _ := f.Get(pad(0))
	uassert.Equal(t, "updated", v)
}

// TestDescendingInsertionIsTheSlowPath exercises the worst case for a sorted
// vector — every insert shifts the whole tail — and checks it stays correct.
func TestDescendingInsertionIsTheSlowPath(t *testing.T) {
	f := New()
	for i := 200; i > 0; i-- {
		f.Set(pad(i), strconv.Itoa(i))
	}
	uassert.Equal(t, 200, f.Len())
	uassert.True(t, f.Sorted(), "still sorted after 200 head insertions")

	k, v, _ := f.At(0)
	uassert.Equal(t, pad(1), k)
	uassert.Equal(t, "1", v, "keys and values must stay in step through every shift")
}

func collect(f *FlatMap, lo, hi string) string {
	var out []string
	f.Range(lo, hi, func(k, v string) bool {
		out = append(out, k)
		return false
	})
	return strings.Join(out, ",")
}

// pad zero-pads so string order matches numeric order. ufmt has no width
// flags in gno, so this is done by hand.
func pad(i int) string {
	s := strconv.Itoa(i)
	for len(s) < 6 {
		s = "0" + s
	}
	return s
}
