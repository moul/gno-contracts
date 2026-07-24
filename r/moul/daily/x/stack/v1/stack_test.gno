package stack

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils"
	"gno.land/p/nt/uassert"
)

func resetState() {
	stackData = nil
	queueData = nil
}

// TestStackLIFO checks that the stack pops in reverse order (last in, first out).
func TestStackLIFO(cur realm, t *testing.T) {
	resetState()
	addr := testutils.TestAddress("alice")
	testing.SetRealm(testing.NewUserRealm(addr))

	Push(cross(cur), 1)
	Push(cross(cur), 2)
	Push(cross(cur), 3)
	uassert.Equal(t, 3, StackSize())

	uassert.Equal(t, 3, Pop(cross(cur)))
	uassert.Equal(t, 2, Pop(cross(cur)))
	uassert.Equal(t, 1, Pop(cross(cur)))
	uassert.Equal(t, 0, StackSize())
}

// TestQueueFIFO checks that the queue dequeues in insertion order (first in, first out).
func TestQueueFIFO(cur realm, t *testing.T) {
	resetState()
	addr := testutils.TestAddress("bob")
	testing.SetRealm(testing.NewUserRealm(addr))

	Enqueue(cross(cur), 1)
	Enqueue(cross(cur), 2)
	Enqueue(cross(cur), 3)
	uassert.Equal(t, 3, QueueSize())

	uassert.Equal(t, 1, Dequeue(cross(cur)))
	uassert.Equal(t, 2, Dequeue(cross(cur)))
	uassert.Equal(t, 3, Dequeue(cross(cur)))
	uassert.Equal(t, 0, QueueSize())
}

// TestEmptyPanics checks that popping/dequeuing empty structures aborts.
func TestEmptyPanics(cur realm, t *testing.T) {
	resetState()
	addr := testutils.TestAddress("carol")
	testing.SetRealm(testing.NewUserRealm(addr))

	uassert.AbortsWithMessage(t, "stack is empty: nothing to pop", func() {
		Pop(cross(cur))
	})
	uassert.AbortsWithMessage(t, "queue is empty: nothing to dequeue", func() {
		Dequeue(cross(cur))
	})
}

// TestRender checks that Render reports sizes, labels, and the LIFO/FIFO explanation.
func TestRender(cur realm, t *testing.T) {
	resetState()
	addr := testutils.TestAddress("dave")
	testing.SetRealm(testing.NewUserRealm(addr))

	Push(cross(cur), 7)
	Enqueue(cross(cur), 9)

	out := Render("")
	uassert.True(t, strings.Contains(out, "Stack (LIFO)"), "should label the stack")
	uassert.True(t, strings.Contains(out, "Queue (FIFO)"), "should label the queue")
	uassert.True(t, strings.Contains(out, "Top: `7`"), "should mark the top of the stack")
	uassert.True(t, strings.Contains(out, "Front: `9`"), "should mark the front of the queue")
}
