package bitset

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestSetHasClear(t *testing.T) {
	b := New(100)
	uassert.False(t, b.Has(7))
	uassert.True(t, b.Set(7))
	uassert.True(t, b.Has(7))
	uassert.True(t, b.Clear(7))
	uassert.False(t, b.Has(7))
}

// Out of range is reported, never a panic — and Has is simply false.
func TestOutOfRange(t *testing.T) {
	b := New(64)
	for _, i := range []int{-1, 64, 1000} {
		uassert.False(t, b.Set(i))
		uassert.False(t, b.Clear(i))
		uassert.False(t, b.Flip(i))
		uassert.False(t, b.Has(i))
	}
	uassert.Equal(t, 0, b.Count())
}

// Word boundaries are where an off-by-one lives: check either side of 64.
func TestWordBoundaries(t *testing.T) {
	b := New(200)
	for _, i := range []int{0, 63, 64, 65, 127, 128, 199} {
		uassert.True(t, b.Set(i))
	}
	uassert.Equal(t, 7, b.Count())
	for _, i := range []int{0, 63, 64, 65, 127, 128, 199} {
		uassert.True(t, b.Has(i))
	}
	uassert.False(t, b.Has(62))
	uassert.False(t, b.Has(129))
}

func TestFlip(t *testing.T) {
	b := New(10)
	b.Flip(3)
	uassert.True(t, b.Has(3))
	b.Flip(3)
	uassert.False(t, b.Has(3))
}

func TestCountAndSlice(t *testing.T) {
	b := FromSlice(50, []int{1, 5, 9, 49})
	uassert.Equal(t, 4, b.Count())
	uassert.Equal(t, "1,5,9,49", join(b.Slice()))
}

func TestFromSliceIgnoresOutOfRange(t *testing.T) {
	b := FromSlice(10, []int{1, -3, 10, 99, 4})
	uassert.Equal(t, "1,4", join(b.Slice()))
}

func TestSetAlgebra(t *testing.T) {
	a := FromSlice(20, []int{1, 2, 3})
	b := FromSlice(20, []int{3, 4})
	uassert.Equal(t, "1,2,3,4", join(Union(a, b).Slice()))
	uassert.Equal(t, "3", join(Intersect(a, b).Slice()))
	uassert.Equal(t, "1,2", join(Difference(a, b).Slice()))
	uassert.Equal(t, "1,2,4", join(SymmetricDifference(a, b).Slice()))
}

// Combining different capacities is a caller error: nil, not a silent pad.
func TestMismatchedCapacityIsNil(t *testing.T) {
	a := New(10)
	b := New(20)
	uassert.True(t, Union(a, b) == nil)
	uassert.True(t, Intersect(a, b) == nil)
	uassert.True(t, Difference(a, b) == nil)
	uassert.True(t, SymmetricDifference(a, b) == nil)
	uassert.False(t, Equal(a, b))
}

func TestCloneIsIndependent(t *testing.T) {
	a := FromSlice(30, []int{1, 2})
	c := a.Clone()
	c.Set(29)
	uassert.False(t, a.Has(29))
	uassert.True(t, Equal(a, FromSlice(30, []int{1, 2})))
}

func TestEqual(t *testing.T) {
	uassert.True(t, Equal(FromSlice(8, []int{1, 3}), FromSlice(8, []int{3, 1})))
	uassert.False(t, Equal(FromSlice(8, []int{1}), FromSlice(8, []int{2})))
}

func TestString(t *testing.T) {
	uassert.Equal(t, "01010", FromSlice(5, []int{1, 3}).String())
}

func TestCapClamped(t *testing.T) {
	uassert.Equal(t, 0, New(-5).Cap())
	uassert.Equal(t, MaxBits, New(MaxBits+1000).Cap())
}

func TestPopcount(t *testing.T) {
	uassert.Equal(t, 0, popcount(0))
	uassert.Equal(t, 1, popcount(1))
	uassert.Equal(t, 64, popcount(^uint64(0)))
}

func join(xs []int) string {
	parts := []string{}
	for _, x := range xs {
		parts = append(parts, itoa(x))
	}
	return strings.Join(parts, ",")
}

func itoa(i int) string {
	if i == 0 {
		return "0"
	}
	neg := i < 0
	if neg {
		i = -i
	}
	var b []byte
	for i > 0 {
		b = append([]byte{byte('0' + i%10)}, b...)
		i /= 10
	}
	if neg {
		return "-" + string(b)
	}
	return string(b)
}
