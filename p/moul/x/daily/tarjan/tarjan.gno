// Package tarjan finds the strongly connected components of a directed graph:
// the maximal groups of nodes that can all reach each other.
//
// A strongly connected component answers "which of these things are tangled
// together", which is a different and more useful question than "is there a
// cycle". A dependency checker that only says yes leaves the caller to find the
// knot; this one hands back the knot itself. Collapsing each component to a
// point turns any graph into a DAG, so the components come out already ordered.
//
// The implementation is Tarjan's 1972 single-pass algorithm: one depth-first
// walk, using a low-link number to recognise the root of each component on the
// way back up. It keeps its own explicit stack rather than recursing, so a
// graph deeper than the VM's call stack is still fine, and every ordering it
// depends on is lexicographic rather than map iteration order, so the same
// edges always produce the same answer.
//
// Live demo: [r/moul/x/daily/tarjandemo](/r/moul/x/daily/tarjandemo/v0).
package tarjan

import (
	"sort"
	"strings"
)

// Graph is a directed graph over string node names.
//
// Nodes are stored in insertion order and the map is a name lookup only:
// nothing here is ever read out of a map in map order, because gno map
// iteration order is unspecified and a realm whose Render reshuffled between
// identical calls would be a consensus bug. Every traversal walks a name-sorted
// permutation instead.
type Graph struct {
	names []string       // insertion order; an index into this is stable forever
	index map[string]int // name -> position in names
	succ  [][]int        // per node, successor indices sorted by successor NAME
}

// New returns an empty graph.
func New() *Graph {
	return &Graph{index: make(map[string]int)}
}

// FromPairs builds a graph from {from, to} edges. Nodes are created as they are
// named, so an isolated node needs [Graph.Add].
func FromPairs(pairs [][2]string) *Graph {
	g := New()
	for _, p := range pairs {
		g.Edge(p[0], p[1])
	}
	return g
}

// Add adds a node with no edges. Adding an existing node, or an empty name,
// does nothing.
func (g *Graph) Add(name string) {
	g.node(name)
}

// Edge adds a directed edge from -> to, creating either node as needed. A
// duplicate edge collapses; an edge touching an empty name is ignored.
//
// A self edge is kept: a node that depends on itself is a one-node cycle, and
// [Graph.Cyclic] reports it as one.
func (g *Graph) Edge(from, to string) {
	if from == "" || to == "" {
		return
	}
	f := g.node(from)
	t := g.node(to)
	g.addSucc(f, t)
}

// Nodes returns every node name, sorted. The slice is a copy.
func (g *Graph) Nodes() []string {
	out := make([]string, len(g.names))
	copy(out, g.names)
	sort.Strings(out)
	return out
}

// Successors returns the nodes name points at, sorted. Unknown names and sinks
// both return nothing. The slice is a copy.
func (g *Graph) Successors(name string) []string {
	i, ok := g.index[name]
	if !ok {
		return nil
	}
	out := make([]string, 0, len(g.succ[i]))
	for _, s := range g.succ[i] {
		out = append(out, g.names[s])
	}
	return out
}

// Components returns the strongly connected components.
//
// Each component is sorted lexicographically, and the components themselves
// come out in reverse topological order of the condensation: a component is
// always emitted before any component that can reach it. So the first entry
// depends on nothing outside itself and the last is depended on by nothing.
// That is the order Tarjan's algorithm produces for free, and it is the useful
// one: an install order where each entry is either a single node or a knot that
// has to be handled as a unit.
//
// A node with no cycle through it is a component of exactly one.
func (g *Graph) Components() [][]string {
	n := len(g.names)
	const unvisited = -1

	var (
		idx     = make([]int, n) // discovery number
		low     = make([]int, n) // lowest discovery number reachable from here
		onStack = make([]bool, n)
		stack   []int // the component stack
		next    int
		out     [][]string
	)
	for i := range idx {
		idx[i] = unvisited
	}

	// frame is one level of the walk that recursion would have put on the call
	// stack: the node, and how far through its successors we had got.
	type frame struct {
		node int
		pc   int
	}

	for _, root := range g.sortedNodes() {
		if idx[root] != unvisited {
			continue
		}
		work := []frame{{node: root}}

		for len(work) > 0 {
			top := len(work) - 1
			v := work[top].node

			if work[top].pc == 0 {
				idx[v] = next
				low[v] = next
				next++
				stack = append(stack, v)
				onStack[v] = true
			}

			// Walk the successors, suspending at the first unvisited one.
			descended := false
			for i := work[top].pc; i < len(g.succ[v]); i++ {
				w := g.succ[v][i]
				if idx[w] == unvisited {
					work[top].pc = i + 1
					work = append(work, frame{node: w})
					descended = true
					break
				}
				if onStack[w] && idx[w] < low[v] {
					// w is on the current path, so v reaches back at least as
					// far as w was discovered.
					low[v] = idx[w]
				}
			}
			if descended {
				continue
			}

			// v is finished. Equal numbers mean nothing below v reached past
			// it, so v is the root of a component and everything stacked above
			// it belongs to that component.
			if low[v] == idx[v] {
				var comp []string
				for {
					w := stack[len(stack)-1]
					stack = stack[:len(stack)-1]
					onStack[w] = false
					comp = append(comp, g.names[w])
					if w == v {
						break
					}
				}
				sort.Strings(comp)
				out = append(out, comp)
			}

			work = work[:top]
			if top > 0 {
				if p := work[top-1].node; low[v] < low[p] {
					low[p] = low[v]
				}
			}
		}
	}
	return out
}

// ComponentOf returns the component holding name, sorted, or nothing if the
// graph does not have that node. A node in no cycle is alone in its own
// component, so this never returns an empty non-nil slice.
func (g *Graph) ComponentOf(name string) []string {
	if _, ok := g.index[name]; !ok {
		return nil
	}
	for _, comp := range g.Components() {
		for _, c := range comp {
			if c == name {
				return comp
			}
		}
	}
	return nil // unreachable: every known node is in exactly one component
}

// Cyclic reports whether any cycle exists, self edges included.
//
// It cannot be answered by component size alone: a node pointing at itself is a
// cycle and its component holds exactly one node, the same size as every
// acyclic node's. So a one-node component is only acyclic when the node does
// not point at itself.
func (g *Graph) Cyclic() bool {
	for _, comp := range g.Components() {
		if len(comp) > 1 {
			return true
		}
		i := g.index[comp[0]]
		for _, s := range g.succ[i] {
			if s == i {
				return true
			}
		}
	}
	return false
}

// String renders the adjacency list, one node per line in sorted order, as
// "node -> a, b" or just "node" for a sink. The empty graph is the empty
// string.
func (g *Graph) String() string {
	var b strings.Builder
	for _, i := range g.sortedNodes() {
		b.WriteString(g.names[i])
		if len(g.succ[i]) > 0 {
			b.WriteString(" -> ")
			for j, s := range g.succ[i] {
				if j > 0 {
					b.WriteString(", ")
				}
				b.WriteString(g.names[s])
			}
		}
		b.WriteByte('\n')
	}
	return b.String()
}

// node returns the index of name, appending it if new. An empty name is refused
// and reported as -1. Indices are never reused or shifted, so one stays valid
// for the life of the graph.
func (g *Graph) node(name string) int {
	if name == "" {
		return -1
	}
	if i, ok := g.index[name]; ok {
		return i
	}
	i := len(g.names)
	g.names = append(g.names, name)
	g.succ = append(g.succ, nil)
	g.index[name] = i
	return i
}

// addSucc records the edge f -> t, keeping g.succ[f] sorted by successor name
// and free of duplicates. Sorting by name rather than by index is what makes
// the traversal independent of the order the edges were declared in.
func (g *Graph) addSucc(f, t int) {
	name := g.names[t]
	s := g.succ[f]

	lo, hi := 0, len(s)
	for lo < hi {
		mid := (lo + hi) / 2
		if g.names[s[mid]] < name {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	if lo < len(s) && s[lo] == t {
		return
	}

	s = append(s, 0)
	copy(s[lo+1:], s[lo:])
	s[lo] = t
	g.succ[f] = s
}

// sortedNodes returns node indices ordered by name. gno has no sort.Slice, so
// the permutation goes through an explicit sort.Interface.
func (g *Graph) sortedNodes() []int {
	order := make([]int, len(g.names))
	for i := range order {
		order[i] = i
	}
	sort.Sort(byName{order: order, names: g.names})
	return order
}

// byName orders a permutation of node indices by the name each one points at.
type byName struct {
	order []int
	names []string
}

func (b byName) Len() int           { return len(b.order) }
func (b byName) Less(i, j int) bool { return b.names[b.order[i]] < b.names[b.order[j]] }
func (b byName) Swap(i, j int)      { b.order[i], b.order[j] = b.order[j], b.order[i] }
