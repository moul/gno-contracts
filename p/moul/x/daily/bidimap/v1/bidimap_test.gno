package bidimap

import (
	"strconv"
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestEmpty(t *testing.T) {
	m := New()
	uassert.Equal(t, 0, m.Len())
	uassert.False(t, m.Has("a"))
	uassert.False(t, m.HasValue("1"))
	uassert.True(t, m.Consistent(), "an empty map is consistent")
}

func TestPutAndBothLookups(t *testing.T) {
	m := New()
	_, ok := m.Put("alice", "admin")
	uassert.True(t, ok)

	v, found := m.Get("alice")
	uassert.True(t, found)
	uassert.Equal(t, "admin", v)

	k, found := m.GetKey("admin")
	uassert.True(t, found)
	uassert.Equal(t, "alice", k, "the reverse lookup is the point of the type")

	uassert.True(t, m.Has("alice"))
	uassert.True(t, m.HasValue("admin"))
	uassert.True(t, m.Consistent())
}

func TestMissingLookups(t *testing.T) {
	m := New()
	m.Put("a", "1")

	_, ok := m.Get("nope")
	uassert.False(t, ok)
	_, ok = m.GetKey("nope")
	uassert.False(t, ok)
}

// TestPutReplacesOnKeySide is the invariant that a naive pair-of-maps breaks:
// rebinding a key must drop the old value from the reverse index too.
func TestPutReplacesOnKeySide(t *testing.T) {
	m := New()
	m.Put("alice", "admin")

	evicted, ok := m.Put("alice", "auditor")
	uassert.True(t, ok)
	uassert.Equal(t, 1, len(evicted))
	uassert.Equal(t, "alice", evicted[0][0])
	uassert.Equal(t, "admin", evicted[0][1])

	uassert.False(t, m.HasValue("admin"), "the stale value must leave the reverse index")
	uassert.Equal(t, 1, m.Len())
	uassert.True(t, m.Consistent())
}

// TestPutReplacesOnValueSide is the mirror case: stealing a value must unbind
// whoever held it.
func TestPutReplacesOnValueSide(t *testing.T) {
	m := New()
	m.Put("alice", "admin")

	evicted, ok := m.Put("bob", "admin")
	uassert.True(t, ok)
	uassert.Equal(t, 1, len(evicted))
	uassert.Equal(t, "alice", evicted[0][0])

	uassert.False(t, m.Has("alice"), "alice lost her binding to bob")
	k, _ := m.GetKey("admin")
	uassert.Equal(t, "bob", k)
	uassert.Equal(t, 1, m.Len())
	uassert.True(t, m.Consistent())
}

// TestPutEvictsBothSides covers the case where the new pair displaces two
// different existing pairs at once.
func TestPutEvictsBothSides(t *testing.T) {
	m := New()
	m.Put("alice", "admin")
	m.Put("bob", "auditor")

	evicted, ok := m.Put("alice", "auditor")
	uassert.True(t, ok)
	uassert.Equal(t, 2, len(evicted), "displaces alice->admin and bob->auditor")

	uassert.Equal(t, 1, m.Len())
	uassert.False(t, m.Has("bob"))
	uassert.False(t, m.HasValue("admin"))
	uassert.True(t, m.Consistent())
}

func TestPutIdenticalPairIsNoop(t *testing.T) {
	m := New()
	m.Put("a", "1")
	evicted, ok := m.Put("a", "1")
	uassert.True(t, ok)
	uassert.Equal(t, 0, len(evicted), "re-putting the same pair evicts nothing")
	uassert.Equal(t, 1, m.Len())
}

func TestPutUniqueRefuses(t *testing.T) {
	m := New()
	uassert.True(t, m.PutUnique("alice", "admin"))

	uassert.False(t, m.PutUnique("alice", "auditor"), "key already bound")
	uassert.False(t, m.PutUnique("bob", "admin"), "value already bound")
	uassert.True(t, m.PutUnique("alice", "admin"), "identical pair is idempotent")

	// Nothing changed.
	uassert.Equal(t, 1, m.Len())
	v, _ := m.Get("alice")
	uassert.Equal(t, "admin", v)
	uassert.True(t, m.Consistent())
}

func TestDelete(t *testing.T) {
	m := New()
	m.Put("a", "1")

	uassert.True(t, m.Delete("a"))
	uassert.Equal(t, 0, m.Len())
	uassert.False(t, m.HasValue("1"), "delete clears the reverse index too")
	uassert.False(t, m.Delete("a"), "deleting twice reports false")
	uassert.True(t, m.Consistent())
}

func TestDeleteValue(t *testing.T) {
	m := New()
	m.Put("a", "1")

	uassert.True(t, m.DeleteValue("1"))
	uassert.False(t, m.Has("a"), "delete-by-value clears the forward index too")
	uassert.False(t, m.DeleteValue("1"))
	uassert.True(t, m.Consistent())
}

// TestKeysAndValuesAreSorted is the determinism guarantee.
func TestKeysAndValuesAreSorted(t *testing.T) {
	m := New()
	m.Put("delta", "4")
	m.Put("alpha", "1")
	m.Put("charlie", "3")

	uassert.Equal(t, "alpha,charlie,delta", strings.Join(m.Keys(), ","))
	uassert.Equal(t, "1,3,4", strings.Join(m.Values(), ","))
}

func TestIterateSortedAndStops(t *testing.T) {
	m := New()
	m.Put("b", "2")
	m.Put("a", "1")
	m.Put("c", "3")

	var seen []string
	m.Iterate(func(k, v string) bool {
		seen = append(seen, k+"="+v)
		return false
	})
	uassert.Equal(t, "a=1,b=2,c=3", strings.Join(seen, ","))

	var first []string
	m.Iterate(func(k, v string) bool {
		first = append(first, k)
		return true // stop immediately
	})
	uassert.Equal(t, 1, len(first))
	uassert.Equal(t, "a", first[0])
}

func TestInvert(t *testing.T) {
	m := New()
	m.Put("alice", "admin")
	m.Put("bob", "auditor")

	inv := m.Invert()
	v, ok := inv.Get("admin")
	uassert.True(t, ok)
	uassert.Equal(t, "alice", v)
	uassert.True(t, inv.Consistent())

	// Independent of the original.
	inv.Delete("admin")
	uassert.Equal(t, 2, m.Len())
}

func TestClone(t *testing.T) {
	m := New()
	m.Put("a", "1")

	cp := m.Clone()
	cp.Put("b", "2")

	uassert.Equal(t, 1, m.Len(), "clone must not share storage")
	uassert.Equal(t, 2, cp.Len())
	uassert.True(t, cp.Consistent())
}

func TestMaxPairs(t *testing.T) {
	m := New()
	for i := 0; i < MaxPairs; i++ {
		s := strconv.Itoa(i)
		_, ok := m.Put("k"+s, "v"+s)
		uassert.True(t, ok, "should accept up to MaxPairs")
	}
	uassert.Equal(t, MaxPairs, m.Len())

	_, ok := m.Put("overflow", "value")
	uassert.False(t, ok, "a full map refuses a wholly new pair")
	uassert.False(t, m.PutUnique("overflow", "value"))
	uassert.Equal(t, MaxPairs, m.Len())
}

// TestFullMapStillRebinds pins the subtler half of the capacity rule: a full
// map still accepts a Put that rebinds an existing key or steals an existing
// value, because that reuses a slot rather than growing the map. Only a pair
// new on BOTH sides is refused.
func TestFullMapStillRebinds(t *testing.T) {
	m := New()
	for i := 0; i < MaxPairs; i++ {
		s := strconv.Itoa(i)
		m.Put("k"+s, "v"+s)
	}

	// New value, existing key -> reuses k0's slot, so it is allowed.
	evicted, ok := m.Put("k0", "brand-new-value")
	uassert.True(t, ok, "rebinding an existing key does not grow a full map")
	uassert.Equal(t, 1, len(evicted))
	uassert.Equal(t, "v0", evicted[0][1])

	v, _ := m.Get("k0")
	uassert.Equal(t, "brand-new-value", v)
	uassert.Equal(t, MaxPairs, m.Len(), "size is unchanged")
	uassert.True(t, m.Consistent())

	// New key, existing value -> reuses that value's slot, also allowed.
	_, ok = m.Put("brand-new-key", "v1")
	uassert.True(t, ok, "stealing an existing value does not grow a full map")
	uassert.Equal(t, MaxPairs, m.Len())
	uassert.False(t, m.Has("k1"), "k1 lost its binding")
	uassert.True(t, m.Consistent())

	// New on both sides -> refused, and nothing changes.
	_, ok = m.Put("wholly", "new")
	uassert.False(t, ok, "a full map refuses a pair new on both sides")
	uassert.Equal(t, MaxPairs, m.Len())
	uassert.True(t, m.Consistent())
}
