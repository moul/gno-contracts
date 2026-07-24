package lru

import (
	"strconv"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

func reset(cur realm) {
	Reset(cross(cur))
}

func TestPutGetAndRecency(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("alice")))
	reset(cur)

	Put(cross(cur), "a", "1")
	Put(cross(cur), "b", "2")

	v, ok := Get(cross(cur), "a")
	uassert.True(t, ok, "a should be present")
	uassert.Equal(t, "1", v)

	// miss
	_, ok = Get(cross(cur), "zzz")
	uassert.False(t, ok, "zzz should be absent")

	// after Get("a"), a is MRU -> head
	uassert.Equal(t, "a", c.head.key)
	uassert.Equal(t, "b", c.tail.key)

	// stats: 1 hit, 1 miss
	uassert.Equal(t, 1, c.hits)
	uassert.Equal(t, 1, c.miss)

	// update existing key
	Put(cross(cur), "b", "22")
	v, _ = peek("b")
	uassert.Equal(t, "22", v)
	uassert.Equal(t, "b", c.head.key) // update marks MRU
	uassert.Equal(t, 2, c.size)
}

func TestEviction(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("bob")))
	reset(cur)

	// fill beyond capacity (8): insert k0..k9
	for i := 0; i < 10; i++ {
		Put(cross(cur), "k"+strconv.Itoa(i), strconv.Itoa(i))
	}

	uassert.Equal(t, capacity, c.size)

	// k0 and k1 should have been evicted (oldest inserts, never touched)
	_, ok := peek("k0")
	uassert.False(t, ok, "k0 should be evicted")
	_, ok = peek("k1")
	uassert.False(t, ok, "k1 should be evicted")

	// newest is MRU head, k2 is now the LRU tail
	uassert.Equal(t, "k9", c.head.key)
	uassert.Equal(t, "k2", c.tail.key)

	// touching k2 protects it; next insert evicts k3 instead
	_, ok = Get(cross(cur), "k2")
	uassert.True(t, ok, "k2 present")
	Put(cross(cur), "k10", "10")
	_, ok = peek("k2")
	uassert.True(t, ok, "k2 protected after Get")
	_, ok = peek("k3")
	uassert.False(t, ok, "k3 evicted instead")
	uassert.Equal(t, capacity, c.size)
}
