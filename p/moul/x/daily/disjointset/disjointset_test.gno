package disjointset

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestSingletons(t *testing.T) {
	d := New(5)
	uassert.Equal(t, 5, d.Len())
	uassert.Equal(t, 5, d.Groups())
	for i := 0; i < 5; i++ {
		uassert.Equal(t, i, d.Find(i))
		uassert.Equal(t, 1, d.Size(i))
	}
}

func TestUnionAndConnected(t *testing.T) {
	d := New(6)
	uassert.True(t, d.Union(0, 1))
	uassert.True(t, d.Union(1, 2))
	uassert.True(t, d.Connected(0, 2))
	uassert.False(t, d.Connected(0, 3))
	uassert.Equal(t, 4, d.Groups()) // {0,1,2} {3} {4} {5}
	uassert.Equal(t, 3, d.Size(0))
}

// Merging an already-merged pair is a no-op and must not lose a group.
func TestUnionIdempotent(t *testing.T) {
	d := New(4)
	uassert.True(t, d.Union(0, 1))
	uassert.False(t, d.Union(0, 1))
	uassert.False(t, d.Union(1, 0))
	uassert.Equal(t, 3, d.Groups())
}

func TestOutOfRange(t *testing.T) {
	d := New(3)
	uassert.Equal(t, -1, d.Find(-1))
	uassert.Equal(t, -1, d.Find(3))
	uassert.False(t, d.Union(0, 99))
	uassert.False(t, d.Union(-1, 0))
	uassert.Equal(t, 0, d.Size(99))
	// out of range is connected to nothing, not even itself
	uassert.False(t, d.Connected(99, 99))
	uassert.Equal(t, 3, d.Groups())
}

// The result must not depend on the order unions were applied.
func TestPartitionIsOrderIndependent(t *testing.T) {
	a := New(7)
	a.Union(0, 1)
	a.Union(2, 3)
	a.Union(1, 3)
	b := New(7)
	b.Union(3, 1)
	b.Union(2, 3)
	b.Union(1, 0)
	uassert.Equal(t, render(a.Partition()), render(b.Partition()))
	uassert.Equal(t, "0,1,2,3|4|5|6", render(a.Partition()))
}

// Path compression must not change what the structure means.
func TestFindCompressesWithoutChangingGroups(t *testing.T) {
	d := New(10)
	for i := 0; i < 9; i++ {
		d.Union(i, i+1) // a long chain, the worst case for an uncompressed find
	}
	uassert.Equal(t, 1, d.Groups())
	root := d.Find(0)
	for i := 0; i < 10; i++ {
		uassert.Equal(t, root, d.Find(i))
	}
	uassert.Equal(t, 10, d.Size(0))
	uassert.Equal(t, "0,1,2,3,4,5,6,7,8,9", render(d.Partition()))
}

func TestEmpty(t *testing.T) {
	d := New(0)
	uassert.Equal(t, 0, d.Len())
	uassert.Equal(t, 0, d.Groups())
	uassert.Equal(t, 0, len(d.Partition()))
}

func TestClamped(t *testing.T) {
	uassert.Equal(t, 0, New(-3).Len())
	uassert.Equal(t, MaxN, New(MaxN+50).Len())
}

func render(groups [][]int) string {
	parts := []string{}
	for _, g := range groups {
		nums := []string{}
		for _, x := range g {
			nums = append(nums, itoa(x))
		}
		parts = append(parts, strings.Join(nums, ","))
	}
	return strings.Join(parts, "|")
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
