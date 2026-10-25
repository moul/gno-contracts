package dijkstra

// queue is the frontier: a binary min-heap of node indices ordered by their
// current distance, with a position table so a node already in the heap can be
// moved up when its distance improves.
//
// The alternative, pushing a second entry and discarding stale pops, is
// shorter and is what a generic priority queue forces on you. It also lets the
// heap grow to one entry per arc, which is the size this package refuses to
// let a caller guess at: here the heap holds at most one entry per node, so
// MaxNodes bounds the memory and MaxEdges bounds only the work.
//
// Ordering is total: distance first, then node index. Node indices are
// assigned in the order AddNode saw them, so an equal-distance tie resolves to
// the order the caller built the graph in, identically on every machine.
type queue struct {
	heap []int // heap positions -> node index
	pos  []int // node index -> heap position, -1 when not queued
	dist []int // the live distance table, read, never written
}

func newQueue(n int, dist []int) *queue {
	q := &queue{dist: dist, pos: make([]int, n)}
	for i := 0; i < n; i++ {
		q.pos[i] = -1
	}
	return q
}

func (q *queue) empty() bool { return len(q.heap) == 0 }

func (q *queue) less(a, b int) bool {
	if q.dist[a] != q.dist[b] {
		return q.dist[a] < q.dist[b]
	}
	return a < b
}

func (q *queue) swap(i, j int) {
	q.heap[i], q.heap[j] = q.heap[j], q.heap[i]
	q.pos[q.heap[i]] = i
	q.pos[q.heap[j]] = j
}

// push queues a node whose distance has just become finite.
func (q *queue) push(node int) {
	q.heap = append(q.heap, node)
	q.pos[node] = len(q.heap) - 1
	q.up(len(q.heap) - 1)
}

// decreased re-sifts a queued node after its distance dropped.
func (q *queue) decreased(node int) { q.up(q.pos[node]) }

// pop removes and returns the closest outstanding node.
func (q *queue) pop() int {
	top := q.heap[0]
	last := len(q.heap) - 1
	q.swap(0, last)
	q.heap = q.heap[:last]
	q.pos[top] = -1
	if last > 0 {
		q.down(0)
	}
	return top
}

func (q *queue) up(i int) {
	for i > 0 {
		parent := (i - 1) / 2
		if !q.less(q.heap[i], q.heap[parent]) {
			break
		}
		q.swap(i, parent)
		i = parent
	}
}

func (q *queue) down(i int) {
	n := len(q.heap)
	for {
		small := i
		if l := 2*i + 1; l < n && q.less(q.heap[l], q.heap[small]) {
			small = l
		}
		if r := 2*i + 2; r < n && q.less(q.heap[r], q.heap[small]) {
			small = r
		}
		if small == i {
			return
		}
		q.swap(i, small)
		i = small
	}
}
