package orderedmap

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestSetGetOrder(t *testing.T) {
	o := New()
	o.Set("z", "1")
	o.Set("a", "2")
	o.Set("m", "3")
	uassert.Equal(t, "z,a,m", strings.Join(o.Keys(), ","))   // insertion, not sorted
	uassert.Equal(t, "1,2,3", strings.Join(o.Values(), ",")) // values follow keys
	v, ok := o.Get("a")
	uassert.True(t, ok)
	uassert.Equal(t, "2", v)
	uassert.Equal(t, 3, o.Len())
}

// Insertion order means FIRST insertion: updating must not move a key.
func TestUpdateKeepsPosition(t *testing.T) {
	o := New()
	o.Set("a", "1")
	o.Set("b", "2")
	o.Set("a", "99")
	uassert.Equal(t, "a,b", strings.Join(o.Keys(), ","))
	v, _ := o.Get("a")
	uassert.Equal(t, "99", v)
	uassert.Equal(t, 2, o.Len())
}

func TestDeletePreservesOrder(t *testing.T) {
	o := New()
	for _, k := range []string{"a", "b", "c", "d"} {
		o.Set(k, k)
	}
	uassert.True(t, o.Delete("b"))
	uassert.Equal(t, "a,c,d", strings.Join(o.Keys(), ","))
	uassert.False(t, o.Has("b"))
	uassert.False(t, o.Delete("b")) // already gone
	uassert.Equal(t, 3, o.Len())
}

// Re-inserting after a delete appends at the END — it is a new insertion.
func TestReinsertAfterDeleteGoesLast(t *testing.T) {
	o := New()
	for _, k := range []string{"a", "b", "c"} {
		o.Set(k, k)
	}
	o.Delete("a")
	o.Set("a", "again")
	uassert.Equal(t, "b,c,a", strings.Join(o.Keys(), ","))
}

func TestMissingKey(t *testing.T) {
	o := New()
	v, ok := o.Get("nope")
	uassert.False(t, ok)
	uassert.Equal(t, "", v)
	uassert.False(t, o.Has("nope"))
}

func TestAt(t *testing.T) {
	o := New()
	o.Set("x", "1")
	o.Set("y", "2")
	k, v, ok := o.At(1)
	uassert.True(t, ok)
	uassert.Equal(t, "y", k)
	uassert.Equal(t, "2", v)
	_, _, ok = o.At(2)
	uassert.False(t, ok)
	_, _, ok = o.At(-1)
	uassert.False(t, ok)
}

func TestIterateStopsEarly(t *testing.T) {
	o := New()
	for _, k := range []string{"a", "b", "c"} {
		o.Set(k, k)
	}
	seen := []string{}
	o.Iterate(func(k, v string) bool {
		seen = append(seen, k)
		return k == "b" // stop after b
	})
	uassert.Equal(t, "a,b", strings.Join(seen, ","))
}

// The whole point: the order is stable across identical builds, where a
// built-in map gives no such guarantee.
func TestOrderIsStable(t *testing.T) {
	build := func() string {
		o := New()
		for _, k := range []string{"delta", "alpha", "charlie", "bravo"} {
			o.Set(k, k)
		}
		return strings.Join(o.Keys(), ",")
	}
	first := build()
	for i := 0; i < 20; i++ {
		uassert.Equal(t, first, build())
	}
	uassert.Equal(t, "delta,alpha,charlie,bravo", first)
}

func TestKeysIsACopy(t *testing.T) {
	o := New()
	o.Set("a", "1")
	ks := o.Keys()
	ks[0] = "mutated"
	uassert.Equal(t, "a", strings.Join(o.Keys(), ","))
}

func TestCloneIsIndependent(t *testing.T) {
	o := New()
	o.Set("a", "1")
	c := o.Clone()
	c.Set("b", "2")
	uassert.Equal(t, "a", strings.Join(o.Keys(), ","))
	uassert.Equal(t, "a,b", strings.Join(c.Keys(), ","))
}

func TestFullMapRejectsNewKeys(t *testing.T) {
	o := New()
	for i := 0; i < MaxKeys; i++ {
		uassert.True(t, o.Set(itoa(i), "v"))
	}
	uassert.False(t, o.Set("overflow", "v")) // new key refused
	uassert.True(t, o.Set("0", "updated"))   // existing key still updatable
	uassert.Equal(t, MaxKeys, o.Len())
}

func itoa(i int) string {
	if i == 0 {
		return "0"
	}
	var b []byte
	for i > 0 {
		b = append([]byte{byte('0' + i%10)}, b...)
		i /= 10
	}
	return string(b)
}
