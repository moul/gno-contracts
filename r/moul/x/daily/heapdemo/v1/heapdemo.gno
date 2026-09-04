// Package heapdemo is a small gnoweb demo of the binary heap / priority queue
// provided by the [p/moul/x/daily/heap](/p/moul/x/daily/heap/v1) library: it
// shows min- and max-ordering and the deterministic tiebreak.
//
// It contains no heap logic of its own. Stateless, so Render is deterministic —
// which is precisely what the library is for.
package heapdemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/x/daily/heap/v1"
)

type job struct {
	name     string
	priority int
}

// queue is the shared workload used by every section below.
var queue = []job{
	{"send email", 5},
	{"pay invoice", 1},
	{"backup db", 3},
	{"rotate keys", 1},
	{"clear cache", 9},
}

// Render renders the demo for gnoweb.
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# Binary Heap\n\n")
	b.WriteString("A priority queue, demoing the ")
	b.WriteString("[`p/moul/x/daily/heap`](/p/moul/x/daily/heap/v1) library.\n\n")

	b.WriteString("## The workload\n\n")
	b.WriteString("| job | priority |\n|---|---|\n")
	for _, j := range queue {
		b.WriteString("| " + j.name + " | " + strconv.Itoa(j.priority) + " |\n")
	}

	b.WriteString("\n## Min-heap — lowest priority first\n\n")
	b.WriteString(popOrder(fill(heap.New())))

	b.WriteString("\n## Max-heap — highest priority first\n\n")
	b.WriteString(popOrder(fill(heap.NewMax())))

	b.WriteString("\n## Ties\n\n")
	b.WriteString("`pay invoice` and `rotate keys` share priority 1. Both heaps pop them ")
	b.WriteString("**oldest-first**: the tiebreak is insertion order and does *not* invert ")
	b.WriteString("with the heap kind.\n\n")

	b.WriteString("> Without a total order, two nodes could pop equal-priority items in ")
	b.WriteString("different sequences and render different pages — a consensus bug, not a ")
	b.WriteString("cosmetic one.\n")
	return b.String()
}

func fill(h *heap.Heap) *heap.Heap {
	for _, j := range queue {
		h.Push(j.name, j.priority)
	}
	return h
}

func popOrder(h *heap.Heap) string {
	var b strings.Builder
	b.WriteString("| # | job | priority |\n|---|---|---|\n")
	i := 0
	for {
		v, p, ok := h.Pop()
		if !ok {
			break
		}
		i++
		b.WriteString("| " + strconv.Itoa(i) + " | " + v + " | " + strconv.Itoa(p) + " |\n")
	}
	return b.String()
}
