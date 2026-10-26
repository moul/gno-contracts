// Package dijkstra finds the cheapest route from one node to every other node
// of a weighted directed graph, as a pure, reusable package.
//
// It is Dijkstra's algorithm with a binary min-heap keyed on node index, so a
// node is never queued twice and the queue never grows past the node count.
// Complexity is O((V+E) log V), and both V and E are capped (MaxNodes,
// MaxEdges) so a realm can reason about the gas before it calls.
//
// The result is *deterministic*. Two nodes sitting at the same distance settle
// in the order they were added to the graph, and a relaxation that merely ties
// the incumbent never replaces it, so the predecessor chain Path walks is the
// same on every node that runs the code. A shortest-path routine that broke
// ties by map iteration order would make a Render differ between validators,
// which is a consensus bug rather than a cosmetic one.
//
// Weights are non-negative by construction: AddEdge panics on a negative one.
// That is not a simplification, it is the precondition the algorithm needs. A
// settled node is never revisited, so one negative edge silently returns a
// wrong answer rather than an error.
//
// A live demo of this package is at
// [r/moul/x/daily/dijkstrademo](/r/moul/x/daily/dijkstrademo/v0).
package dijkstra

import (
	"errors"
	"strings"
)

const (
	// MaxNodes bounds the graph so a caller can size gas up front.
	MaxNodes = 512
	// MaxEdges bounds the arcs for the same reason. Both are deliberately
	// small: this is a package for a realm's routing table, not for a road
	// network.
	MaxEdges = 4000
	// Unreachable is the distance reported for a node no path reaches. It is
	// returned alongside ok=false, never on its own.
	Unreachable = -1
)

// ErrUnknownNode is returned by lookups naming a node the graph never saw.
var ErrUnknownNode = errors.New("dijkstra: unknown node")

type arc struct {
	to     int
	weight int
}

// Graph is a weighted directed graph over named nodes. The zero value is not
// usable, build one with New.
type Graph struct {
	names []string       // node index -> name, in insertion order
	index map[string]int // name -> node index. Looked up, never ranged over
	adj   [][]arc        // node index -> outgoing arcs, in insertion order
	edges int
}

// New returns an empty Graph.
func New() *Graph {
	return &Graph{index: map[string]int{}}
}

// AddNode registers a node with no arcs and returns its index. Adding a node
// twice returns the existing index and changes nothing, which is how a caller
// declares an island that nothing reaches.
//
// It panics on an empty name, and past MaxNodes.
func (g *Graph) AddNode(name string) int {
	if name == "" {
		panic("dijkstra: empty node name")
	}
	if i, ok := g.index[name]; ok {
		return i
	}
	if len(g.names) >= MaxNodes {
		panic("dijkstra: too many nodes")
	}
	i := len(g.names)
	g.names = append(g.names, name)
	g.index[name] = i
	g.adj = append(g.adj, nil)
	return i
}

// AddEdge records a one-way arc from -> to costing weight, registering either
// endpoint that is new. Parallel arcs are kept rather than collapsed: the
// search takes the cheapest, and dropping the others would lose information a
// caller may want to render.
//
// It panics on a negative weight (the algorithm's precondition), on a
// self-loop (it can never shorten a path and is always a caller mistake), and
// past MaxEdges.
func (g *Graph) AddEdge(from, to string, weight int) {
	if weight < 0 {
		panic("dijkstra: negative weight")
	}
	if from == to {
		panic("dijkstra: self-loop")
	}
	if g.edges >= MaxEdges {
		panic("dijkstra: too many edges")
	}
	f := g.AddNode(from)
	t := g.AddNode(to)
	g.adj[f] = append(g.adj[f], arc{to: t, weight: weight})
	g.edges++
}

// AddUndirected records the same cost in both directions. It is two arcs and
// counts as two against MaxEdges, because that is what it is.
func (g *Graph) AddUndirected(a, b string, weight int) {
	g.AddEdge(a, b, weight)
	g.AddEdge(b, a, weight)
}

// Len returns the number of nodes.
func (g *Graph) Len() int { return len(g.names) }

// Edges returns the number of arcs. An AddUndirected call contributes two.
func (g *Graph) Edges() int { return g.edges }

// Names returns the node names in insertion order. The slice is a copy, so a
// caller cannot reorder the graph's own index by sorting it.
func (g *Graph) Names() []string {
	out := make([]string, len(g.names))
	copy(out, g.names)
	return out
}

// Has reports whether the graph knows a node by that name.
func (g *Graph) Has(name string) bool {
	_, ok := g.index[name]
	return ok
}

// Result holds one single-source run. It is a snapshot: mutating the graph
// afterwards does not update it.
type Result struct {
	g      *Graph
	src    int
	dist   []int
	prev   []int
	done   []bool
	order  []int
	relaxs int
}

// From runs the search outward from source and returns the distances to every
// node. It panics when source is not in the graph, because a typo'd source
// silently returning "nothing is reachable" is the failure mode this package
// exists to avoid.
func (g *Graph) From(source string) *Result {
	s, ok := g.index[source]
	if !ok {
		panic("dijkstra: unknown source: " + source)
	}

	n := len(g.names)
	r := &Result{g: g, src: s}
	r.dist = make([]int, n)
	r.prev = make([]int, n)
	r.done = make([]bool, n)
	for i := 0; i < n; i++ {
		r.dist[i] = Unreachable
		r.prev[i] = -1
	}

	q := newQueue(n, r.dist)
	r.dist[s] = 0
	q.push(s)

	for !q.empty() {
		u := q.pop()
		r.done[u] = true
		r.order = append(r.order, u)
		du := r.dist[u]

		for _, a := range g.adj[u] {
			v := a.to
			if r.done[v] {
				// Weights are non-negative, so a settled node can never be
				// improved. This is the line a negative edge would break.
				continue
			}
			cand := du + a.weight
			if r.dist[v] == Unreachable {
				r.dist[v] = cand
				r.prev[v] = u
				r.relaxs++
				q.push(v)
				continue
			}
			if cand < r.dist[v] {
				// Strictly cheaper, never merely equal: a tie leaves the
				// incumbent predecessor in place, which is what makes Path
				// reproducible rather than dependent on arc order.
				r.dist[v] = cand
				r.prev[v] = u
				r.relaxs++
				q.decreased(v)
			}
		}
	}
	return r
}

// Source returns the node the run started from.
func (r *Result) Source() string { return r.g.names[r.src] }

// Dist returns the total weight of the cheapest route to name. ok is false for
// a node no route reaches and for a name the graph does not know, which are
// different mistakes with the same remedy: check Has first if you need to tell
// them apart.
func (r *Result) Dist(name string) (dist int, ok bool) {
	i, known := r.g.index[name]
	if !known || r.dist[i] == Unreachable {
		return Unreachable, false
	}
	return r.dist[i], true
}

// Path returns the cheapest route to name, source first and name last. It
// returns nil when no route reaches name, and a one-element slice for the
// source itself.
func (r *Result) Path(name string) []string {
	i, known := r.g.index[name]
	if !known || r.dist[i] == Unreachable {
		return nil
	}
	var rev []int
	for at := i; at != -1; at = r.prev[at] {
		rev = append(rev, at)
	}
	out := make([]string, len(rev))
	for k, at := range rev {
		out[len(rev)-1-k] = r.g.names[at]
	}
	return out
}

// PathString renders Path joined with sep, or "" when there is no route. It
// exists so a Render does not have to carry its own join loop.
func (r *Result) PathString(name, sep string) string {
	p := r.Path(name)
	if p == nil {
		return ""
	}
	return strings.Join(p, sep)
}

// Via returns the node immediately before name on the cheapest route, and
// false for the source and for anything unreachable.
func (r *Result) Via(name string) (string, bool) {
	i, known := r.g.index[name]
	if !known || r.dist[i] == Unreachable || r.prev[i] == -1 {
		return "", false
	}
	return r.g.names[r.prev[i]], true
}

// Reachable returns how many nodes have a route, the source included.
func (r *Result) Reachable() int {
	return len(r.order)
}

// Order returns the nodes in the sequence the search settled them: the source
// first, then always the closest node still outstanding. That sequence is the
// algorithm, and a demo that shows it teaches more than one that prints only
// the answer.
func (r *Result) Order() []string {
	out := make([]string, len(r.order))
	for i, at := range r.order {
		out[i] = r.g.names[at]
	}
	return out
}

// Relaxations returns how many arcs the run actually improved a distance with.
// It is the honest cost figure: the arc count is what was looked at, this is
// what was paid for.
func (r *Result) Relaxations() int { return r.relaxs }
