// Package stack is an educational data-structure playground that keeps BOTH a
// LIFO stack and a FIFO queue of ints, so you can compare how the two behave.
package stack

import (
	"chain"
	"strconv"
	"strings"
)

// stackData holds the LIFO stack; the last pushed element is the "top".
var stackData []int

// queueData holds the FIFO queue; the oldest enqueued element is the "front".
var queueData []int

// Push adds n to the top of the LIFO stack.
func Push(cur realm, n int) {
	stackData = append(stackData, n)
	chain.Emit("Push", "n", strconv.Itoa(n), "size", strconv.Itoa(len(stackData)))
}

// Pop removes and returns the top element of the LIFO stack.
// It panics (a cross-realm abort) if the stack is empty.
func Pop(cur realm) int {
	if len(stackData) == 0 {
		panic("stack is empty: nothing to pop")
	}
	last := len(stackData) - 1
	n := stackData[last]
	stackData = stackData[:last]
	chain.Emit("Pop", "n", strconv.Itoa(n), "size", strconv.Itoa(len(stackData)))
	return n
}

// Enqueue adds n to the back of the FIFO queue.
func Enqueue(cur realm, n int) {
	queueData = append(queueData, n)
	chain.Emit("Enqueue", "n", strconv.Itoa(n), "size", strconv.Itoa(len(queueData)))
}

// Dequeue removes and returns the front element of the FIFO queue.
// It panics (a cross-realm abort) if the queue is empty.
func Dequeue(cur realm) int {
	if len(queueData) == 0 {
		panic("queue is empty: nothing to dequeue")
	}
	n := queueData[0]
	queueData = queueData[1:]
	chain.Emit("Dequeue", "n", strconv.Itoa(n), "size", strconv.Itoa(len(queueData)))
	return n
}

// StackSize returns the number of elements in the LIFO stack.
func StackSize() int { return len(stackData) }

// QueueSize returns the number of elements in the FIFO queue.
func QueueSize() int { return len(queueData) }

// renderInts formats a slice of ints as a space-separated list, e.g. "1 2 3".
func renderInts(xs []int) string {
	if len(xs) == 0 {
		return "_(empty)_"
	}
	parts := make([]string, len(xs))
	for i, x := range xs {
		parts[i] = strconv.Itoa(x)
	}
	return "`" + strings.Join(parts, " ") + "`"
}

// Render returns a Markdown view of both structures with top/front labeled,
// their sizes, and a one-line explanation of LIFO vs FIFO.
func Render(path string) string {
	var b strings.Builder

	b.WriteString("# Stack & Queue Playground\n\n")
	b.WriteString("A **stack** is LIFO (last in, first out) — the last item pushed is the first popped. ")
	b.WriteString("A **queue** is FIFO (first in, first out) — the first item enqueued is the first dequeued.\n\n")

	b.WriteString("## Stack (LIFO) — size ")
	b.WriteString(strconv.Itoa(len(stackData)))
	b.WriteString("\n\n")
	b.WriteString("Contents (bottom → top): ")
	b.WriteString(renderInts(stackData))
	b.WriteString("\n\n")
	if len(stackData) > 0 {
		b.WriteString("Top: `")
		b.WriteString(strconv.Itoa(stackData[len(stackData)-1]))
		b.WriteString("` — the next `Pop` returns this.\n\n")
	} else {
		b.WriteString("Top: _(none)_ — `Pop` would panic.\n\n")
	}

	b.WriteString("## Queue (FIFO) — size ")
	b.WriteString(strconv.Itoa(len(queueData)))
	b.WriteString("\n\n")
	b.WriteString("Contents (front → back): ")
	b.WriteString(renderInts(queueData))
	b.WriteString("\n\n")
	if len(queueData) > 0 {
		b.WriteString("Front: `")
		b.WriteString(strconv.Itoa(queueData[0]))
		b.WriteString("` — the next `Dequeue` returns this.\n\n")
	} else {
		b.WriteString("Front: _(none)_ — `Dequeue` would panic.\n\n")
	}

	b.WriteString("---\n\n")
	b.WriteString("_Tip: push the same sequence into both, then Pop vs Dequeue to see LIFO reverse it while FIFO preserves order._\n")

	return b.String()
}
