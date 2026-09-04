// Package heap is a binary min-heap / priority queue over string items with
// integer priorities, as a pure, reusable package.
//
// Go's container/heap makes the caller implement five methods and hands back an
// interface; that indirection buys generality this chain does not need and
// costs gas it does. This is the concrete data structure instead: an implicit
// binary heap in a slice, Push/Pop in O(log n), Peek in O(1).
//
// Ordering is TOTAL and deterministic. Equal priorities are broken by insertion
// sequence, so two heaps fed the same items in the same order always pop the
// same sequence — a heap that reordered ties by allocation address would make a
// Render vary between nodes, which is a consensus bug rather than a cosmetic
// one.
//
// A live demo of this package is at
// [r/moul/x/daily/heapdemo](/r/moul/x/daily/heapdemo/v1).
package heap

// MaxItems bounds the heap so gas stays predictable.
const MaxItems = 4096

type item struct {
	value    string
	priority int
	seq      int // insertion sequence, breaks priority ties
}

// Heap is a binary min-heap: the lowest priority pops first.
type Heap struct {
	items []item
	next  int // monotonic insertion counter
	max   bool
}

// New returns an empty min-heap (lowest priority pops first).
func New() *Heap { return &Heap{} }

// NewMax returns an empty max-heap (highest priority pops first). Ties are
// still broken by insertion order, oldest first.
func NewMax() *Heap { return &Heap{max: true} }

// Len returns the number of items.
func (h *Heap) Len() int { return len(h.items) }

// IsEmpty reports whether the heap holds nothing.
func (h *Heap) IsEmpty() bool { return len(h.items) == 0 }

// IsMax reports whether this is a max-heap.
func (h *Heap) IsMax() bool { return h.max }

// less reports whether a should pop before b.
func (h *Heap) less(a, b item) bool {
	if a.priority != b.priority {
		if h.max {
			return a.priority > b.priority
		}
		return a.priority < b.priority
	}
	// Total order: equal priorities pop oldest-first, in BOTH heap kinds.
	return a.seq < b.seq
}

// Push adds value with the given priority. Returns false when the heap is full.
func (h *Heap) Push(value string, priority int) bool {
	if len(h.items) >= MaxItems {
		return false
	}
	h.items = append(h.items, item{value: value, priority: priority, seq: h.next})
	h.next++
	h.up(len(h.items) - 1)
	return true
}

// Peek returns the item that would pop next, without removing it.
func (h *Heap) Peek() (value string, priority int, ok bool) {
	if len(h.items) == 0 {
		return "", 0, false
	}
	return h.items[0].value, h.items[0].priority, true
}

// Pop removes and returns the next item.
func (h *Heap) Pop() (value string, priority int, ok bool) {
	if len(h.items) == 0 {
		return "", 0, false
	}
	top := h.items[0]
	last := len(h.items) - 1
	h.items[0] = h.items[last]
	h.items = h.items[:last]
	if len(h.items) > 0 {
		h.down(0)
	}
	return top.value, top.priority, true
}

// Drain pops everything, returning values in pop order. The heap ends empty.
func (h *Heap) Drain() []string {
	out := make([]string, 0, len(h.items))
	for {
		v, _, ok := h.Pop()
		if !ok {
			return out
		}
		out = append(out, v)
	}
}

// Clone returns an independent copy.
func (h *Heap) Clone() *Heap {
	cp := &Heap{items: make([]item, len(h.items)), next: h.next, max: h.max}
	copy(cp.items, h.items)
	return cp
}

func (h *Heap) up(i int) {
	for i > 0 {
		parent := (i - 1) / 2
		if !h.less(h.items[i], h.items[parent]) {
			return
		}
		h.items[i], h.items[parent] = h.items[parent], h.items[i]
		i = parent
	}
}

func (h *Heap) down(i int) {
	n := len(h.items)
	for {
		left := 2*i + 1
		if left >= n {
			return
		}
		best := left
		if right := left + 1; right < n && h.less(h.items[right], h.items[left]) {
			best = right
		}
		if !h.less(h.items[best], h.items[i]) {
			return
		}
		h.items[i], h.items[best] = h.items[best], h.items[i]
		i = best
	}
}
