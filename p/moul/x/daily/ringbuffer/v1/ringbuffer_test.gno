package ringbuffer

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestPushPopFIFO(t *testing.T) {
	r := New(3)
	r.Push("a")
	r.Push("b")
	uassert.Equal(t, 2, r.Len())
	v, ok := r.Pop()
	uassert.True(t, ok)
	uassert.Equal(t, "a", v)
	v, _ = r.Pop()
	uassert.Equal(t, "b", v)
	_, ok = r.Pop()
	uassert.False(t, ok)
}

// The defining behaviour: full means overwrite the oldest, and say so.
func TestOverwriteOldest(t *testing.T) {
	r := New(3)
	for _, s := range []string{"a", "b", "c"} {
		ev, dropped := r.Push(s)
		uassert.False(t, dropped)
		uassert.Equal(t, "", ev)
	}
	uassert.True(t, r.Full())
	ev, dropped := r.Push("d")
	uassert.True(t, dropped)
	uassert.Equal(t, "a", ev) // the OLDEST went, not the newest
	uassert.Equal(t, "b,c,d", strings.Join(r.Slice(), ","))
	uassert.Equal(t, 3, r.Len())
}

// Wrapping must not corrupt order — the classic ring-buffer bug.
func TestWrapAroundKeepsOrder(t *testing.T) {
	r := New(3)
	for _, s := range []string{"1", "2", "3", "4", "5", "6", "7"} {
		r.Push(s)
	}
	uassert.Equal(t, "5,6,7", strings.Join(r.Slice(), ","))
	v, _ := r.Peek()
	uassert.Equal(t, "5", v)
}

// Interleaving Pop and Push moves head and tail independently.
func TestInterleavedPushPop(t *testing.T) {
	r := New(3)
	r.Push("a")
	r.Push("b")
	r.Pop() // drop a
	r.Push("c")
	r.Push("d") // fills: b,c,d
	uassert.Equal(t, "b,c,d", strings.Join(r.Slice(), ","))
	ev, dropped := r.Push("e")
	uassert.True(t, dropped)
	uassert.Equal(t, "b", ev)
	uassert.Equal(t, "c,d,e", strings.Join(r.Slice(), ","))
}

func TestAt(t *testing.T) {
	r := New(3)
	r.Push("a")
	r.Push("b")
	v, ok := r.At(0)
	uassert.True(t, ok)
	uassert.Equal(t, "a", v) // 0 is the OLDEST
	v, _ = r.At(1)
	uassert.Equal(t, "b", v)
	_, ok = r.At(2)
	uassert.False(t, ok)
	_, ok = r.At(-1)
	uassert.False(t, ok)
}

// A zero-capacity buffer stores nothing and admits it rather than pretending.
func TestZeroCapacity(t *testing.T) {
	r := New(0)
	uassert.Equal(t, 0, r.Cap())
	ev, dropped := r.Push("x")
	uassert.True(t, dropped)
	uassert.Equal(t, "x", ev)
	uassert.True(t, r.Empty())
	uassert.False(t, r.Full()) // a buffer that holds nothing is never "full"
	uassert.Equal(t, 0, len(r.Slice()))
}

func TestEmptyPeekPop(t *testing.T) {
	r := New(2)
	_, ok := r.Peek()
	uassert.False(t, ok)
	_, ok = r.Pop()
	uassert.False(t, ok)
}

func TestReset(t *testing.T) {
	r := New(3)
	r.Push("a")
	r.Push("b")
	r.Reset()
	uassert.True(t, r.Empty())
	uassert.Equal(t, 0, r.Len())
	r.Push("z")
	uassert.Equal(t, "z", strings.Join(r.Slice(), ","))
}

func TestSliceIsACopy(t *testing.T) {
	r := New(3)
	r.Push("a")
	s := r.Slice()
	s[0] = "mutated"
	uassert.Equal(t, "a", strings.Join(r.Slice(), ","))
}

func TestCapClamped(t *testing.T) {
	uassert.Equal(t, 0, New(-5).Cap())
	uassert.Equal(t, MaxCap, New(MaxCap+100).Cap())
}
