package heap

import (
	"strconv"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestEmpty(t *testing.T) {
	h := New()
	uassert.Equal(t, 0, h.Len())
	uassert.True(t, h.IsEmpty(), "a new heap is empty")

	_, _, ok := h.Peek()
	uassert.False(t, ok, "peek on empty returns not-ok")
	_, _, ok = h.Pop()
	uassert.False(t, ok, "pop on empty returns not-ok")
}

func TestMinOrder(t *testing.T) {
	h := New()
	for _, c := range []struct {
		v string
		p int
	}{{"c", 3}, {"a", 1}, {"d", 4}, {"b", 2}} {
		uassert.True(t, h.Push(c.v, c.p), "push should succeed")
	}
	uassert.Equal(t, 4, h.Len())

	v, p, ok := h.Peek()
	uassert.True(t, ok)
	uassert.Equal(t, "a", v)
	uassert.Equal(t, 1, p)
	uassert.Equal(t, 4, h.Len(), "peek must not remove")

	uassert.Equal(t, "a,b,c,d", join(h.Drain()))
	uassert.True(t, h.IsEmpty(), "drain empties the heap")
}

func TestMaxOrder(t *testing.T) {
	h := NewMax()
	uassert.True(t, h.IsMax(), "NewMax builds a max-heap")
	for _, c := range []struct {
		v string
		p int
	}{{"c", 3}, {"a", 1}, {"d", 4}, {"b", 2}} {
		h.Push(c.v, c.p)
	}
	uassert.Equal(t, "d,c,b,a", join(h.Drain()))
}

// TestTiesBreakByInsertionOrder is the determinism guarantee: equal priorities
// pop oldest-first, so the same input always yields the same output.
func TestTiesBreakByInsertionOrder(t *testing.T) {
	h := New()
	h.Push("first", 5)
	h.Push("second", 5)
	h.Push("third", 5)
	uassert.Equal(t, "first,second,third", join(h.Drain()))
}

// TestTiesBreakOldestFirstInMaxHeap pins that the tiebreak does NOT invert with
// the heap kind — only the priority comparison does.
func TestTiesBreakOldestFirstInMaxHeap(t *testing.T) {
	h := NewMax()
	h.Push("first", 5)
	h.Push("second", 5)
	h.Push("third", 5)
	uassert.Equal(t, "first,second,third", join(h.Drain()))
}

// TestDeterministicAcrossEqualInput feeds two heaps identically and requires
// identical output — the property a Render depends on.
func TestDeterministicAcrossEqualInput(t *testing.T) {
	build := func() *Heap {
		h := New()
		for i := 0; i < 50; i++ {
			h.Push("v"+strconv.Itoa(i), i%7)
		}
		return h
	}
	uassert.Equal(t, join(build().Drain()), join(build().Drain()))
}

func TestInterleavedPushPop(t *testing.T) {
	h := New()
	h.Push("b", 2)
	h.Push("d", 4)

	v, _, _ := h.Pop()
	uassert.Equal(t, "b", v)

	h.Push("a", 1)
	h.Push("c", 3)

	uassert.Equal(t, "a,c,d", join(h.Drain()))
}

func TestNegativeAndZeroPriorities(t *testing.T) {
	h := New()
	h.Push("zero", 0)
	h.Push("neg", -10)
	h.Push("pos", 10)
	uassert.Equal(t, "neg,zero,pos", join(h.Drain()))
}

func TestDuplicateValues(t *testing.T) {
	h := New()
	h.Push("same", 2)
	h.Push("same", 1)
	// Duplicate values are independent entries, ordered by priority.
	uassert.Equal(t, 2, h.Len())
	uassert.Equal(t, "same,same", join(h.Drain()))
}

func TestClone(t *testing.T) {
	h := New()
	h.Push("a", 1)
	h.Push("b", 2)

	cp := h.Clone()
	cp.Pop()

	uassert.Equal(t, 2, h.Len(), "clone must not share storage")
	uassert.Equal(t, 1, cp.Len())
	uassert.Equal(t, "a,b", join(h.Drain()))
}

func TestCloneKeepsKind(t *testing.T) {
	uassert.True(t, NewMax().Clone().IsMax(), "clone of a max-heap is a max-heap")
	uassert.False(t, New().Clone().IsMax(), "clone of a min-heap is a min-heap")
}

func TestMaxItems(t *testing.T) {
	h := New()
	for i := 0; i < MaxItems; i++ {
		uassert.True(t, h.Push("v", i), "should accept up to MaxItems")
	}
	uassert.Equal(t, MaxItems, h.Len())
	uassert.False(t, h.Push("overflow", 0), "a full heap refuses new items")
	uassert.Equal(t, MaxItems, h.Len(), "a refused push must not grow the heap")
}

// TestHeapPropertyHolds drains a pseudo-random load and checks the sequence is
// non-decreasing — the invariant, independent of the insertion pattern.
func TestHeapPropertyHolds(t *testing.T) {
	h := New()
	x := 7
	for i := 0; i < 200; i++ {
		x = (x*31 + 17) % 101 // deterministic spread, no rand
		h.Push("v"+strconv.Itoa(i), x)
	}

	prev := -1
	for {
		_, p, ok := h.Pop()
		if !ok {
			break
		}
		uassert.True(t, p >= prev, "pop order must be non-decreasing")
		prev = p
	}
}

func join(ss []string) string {
	out := ""
	for i, s := range ss {
		if i > 0 {
			out += ","
		}
		out += s
	}
	return out
}
