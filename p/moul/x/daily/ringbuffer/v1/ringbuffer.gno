// Package ringbuffer is a fixed-capacity FIFO that overwrites its oldest entry
// when full, as a pure, reusable package.
//
// This is the bounded cousin of an unbounded queue, and the bound is the point:
// on chain an unbounded queue is an unbounded storage bill, whereas a ring
// buffer's cost is decided once, at construction. It is the right shape for
// "last N events", "recent messages", or any rolling window.
//
// Backed by a flat slice with head/length indices — no per-element allocation,
// no shifting on Pop.
//
// A live demo of this package is at
// [r/moul/x/daily/ringbufferdemo](/r/moul/x/daily/ringbufferdemo/v1).
package ringbuffer

// MaxCap bounds a buffer so allocation stays predictable.
const MaxCap = 4096

// RingBuffer is a fixed-capacity FIFO of strings.
type RingBuffer struct {
	buf  []string
	head int // index of the oldest element
	n    int // number of live elements
}

// New returns an empty buffer of the given capacity, clamped to [0, MaxCap].
func New(capacity int) *RingBuffer {
	if capacity < 0 {
		capacity = 0
	}
	if capacity > MaxCap {
		capacity = MaxCap
	}
	return &RingBuffer{buf: make([]string, capacity)}
}

// Cap returns the capacity.
func (r *RingBuffer) Cap() int { return len(r.buf) }

// Len returns how many elements are live.
func (r *RingBuffer) Len() int { return r.n }

// Full reports whether the next Push will overwrite.
func (r *RingBuffer) Full() bool { return len(r.buf) > 0 && r.n == len(r.buf) }

// Empty reports whether there is nothing to read.
func (r *RingBuffer) Empty() bool { return r.n == 0 }

// Push appends v. When the buffer is full the OLDEST element is dropped to make
// room, and that element is returned with dropped=true — losing data silently
// is the one thing a rolling window must not do.
//
// A zero-capacity buffer accepts nothing and reports the value straight back.
func (r *RingBuffer) Push(v string) (evicted string, dropped bool) {
	if len(r.buf) == 0 {
		return v, true
	}
	if r.n == len(r.buf) {
		evicted = r.buf[r.head]
		r.buf[r.head] = v
		r.head = (r.head + 1) % len(r.buf)
		return evicted, true
	}
	r.buf[(r.head+r.n)%len(r.buf)] = v
	r.n++
	return "", false
}

// Pop removes and returns the oldest element; ok is false when empty.
func (r *RingBuffer) Pop() (v string, ok bool) {
	if r.n == 0 {
		return "", false
	}
	v = r.buf[r.head]
	r.buf[r.head] = "" // release the reference; don't pin a string we no longer own
	r.head = (r.head + 1) % len(r.buf)
	r.n--
	return v, true
}

// Peek returns the oldest element without removing it.
func (r *RingBuffer) Peek() (v string, ok bool) {
	if r.n == 0 {
		return "", false
	}
	return r.buf[r.head], true
}

// At returns the i-th element counting from the oldest (0 = oldest).
func (r *RingBuffer) At(i int) (v string, ok bool) {
	if i < 0 || i >= r.n {
		return "", false
	}
	return r.buf[(r.head+i)%len(r.buf)], true
}

// Slice returns the live elements oldest-first, as an independent copy.
func (r *RingBuffer) Slice() []string {
	out := make([]string, 0, r.n)
	for i := 0; i < r.n; i++ {
		out = append(out, r.buf[(r.head+i)%len(r.buf)])
	}
	return out
}

// Reset empties the buffer, releasing every stored reference.
func (r *RingBuffer) Reset() {
	for i := range r.buf {
		r.buf[i] = ""
	}
	r.head, r.n = 0, 0
}
