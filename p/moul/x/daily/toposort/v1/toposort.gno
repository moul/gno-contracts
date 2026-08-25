// Package toposort orders a dependency graph so that every node comes after
// everything it depends on — the "install these packages in a safe order"
// problem — as a pure, reusable package.
//
// It uses Kahn's algorithm, and it is *deterministic*: ready nodes are always
// taken in lexicographic order, so a given graph always yields the exact same
// ordering. That matters on-chain, where a Render that reshuffled between
// identical calls would be a bug. Adjacency is kept in sorted slices rather
// than maps for the same reason — Go/gno map iteration order is unspecified.
//
// A cycle is reported as an error naming the nodes still stuck, rather than
// panicking or silently dropping them.
//
// A live demo of this package is at
// [r/moul/x/daily/toposortdemo](/r/moul/x/daily/toposortdemo/v1).
package toposort

import (
	"errors"
	"sort"
	"strings"
)

// ErrCycle is returned by Sort when the graph is not a DAG. Use CycleNodes to
// recover which nodes are involved.
var ErrCycle = errors.New("toposort: graph has a cycle")

// Graph is a directed dependency graph. The zero value is not usable — build
// one with New.
type Graph struct {
	nodes []string            // every known node, kept sorted and unique
	deps  map[string][]string // node -> the nodes it depends on (sorted, unique)
}

// New returns an empty Graph.
func New() *Graph {
	return &Graph{deps: map[string][]string{}}
}

// Add registers a node with no dependencies. Adding twice is a no-op; it is
// how you declare a leaf that nothing depends on.
func (g *Graph) Add(node string) {
	if node == "" {
		return
	}
	g.addNode(node)
}

// DependOn records that node depends on dep, so dep must come first. Both
// endpoints are registered. A self-dependency is ignored (it would be a
// trivial cycle and is never what the caller means). Duplicate edges collapse.
func (g *Graph) DependOn(node, dep string) {
	if node == "" || dep == "" {
		return
	}
	g.addNode(node)
	g.addNode(dep)
	if node == dep {
		// A self-edge is a trivial cycle and never what the caller means, but
		// the node was still named, so it stays in the graph as a leaf.
		return
	}
	cur := g.deps[node]
	i := sort.SearchStrings(cur, dep)
	if i < len(cur) && cur[i] == dep {
		return // already recorded
	}
	cur = append(cur, "")
	copy(cur[i+1:], cur[i:])
	cur[i] = dep
	g.deps[node] = cur
}

// addNode inserts node into the sorted node list if absent.
func (g *Graph) addNode(node string) {
	i := sort.SearchStrings(g.nodes, node)
	if i < len(g.nodes) && g.nodes[i] == node {
		return
	}
	g.nodes = append(g.nodes, "")
	copy(g.nodes[i+1:], g.nodes[i:])
	g.nodes[i] = node
}

// Len returns how many nodes the graph holds.
func (g *Graph) Len() int { return len(g.nodes) }

// Nodes returns every node in lexicographic order.
func (g *Graph) Nodes() []string {
	out := make([]string, len(g.nodes))
	copy(out, g.nodes)
	return out
}

// DependenciesOf returns node's direct dependencies, sorted.
func (g *Graph) DependenciesOf(node string) []string {
	d := g.deps[node]
	out := make([]string, len(d))
	copy(out, d)
	return out
}

// Sort returns the nodes ordered so every node follows its dependencies.
//
// Among nodes that are simultaneously ready, the lexicographically smallest is
// emitted first, which makes the result unique for a given graph. On a cycle it
// returns ErrCycle along with the partial order computed so far.
func (g *Graph) Sort() ([]string, error) {
	// indegree[n] = how many of n's dependencies are still unresolved.
	indegree := map[string]int{}
	// dependents[d] = nodes waiting on d.
	dependents := map[string][]string{}
	for _, n := range g.nodes {
		indegree[n] = len(g.deps[n])
		for _, d := range g.deps[n] {
			dependents[d] = append(dependents[d], n)
		}
	}

	// ready holds nodes with no unresolved dependency, kept sorted so the
	// smallest is always taken first.
	ready := []string{}
	for _, n := range g.nodes { // g.nodes is already sorted
		if indegree[n] == 0 {
			ready = append(ready, n)
		}
	}

	out := make([]string, 0, len(g.nodes))
	for len(ready) > 0 {
		n := ready[0]
		ready = ready[1:]
		out = append(out, n)

		// Releasing dependents can make several ready at once; collect them and
		// merge into the sorted queue so ordering stays deterministic.
		freed := []string{}
		for _, m := range dependents[n] {
			indegree[m]--
			if indegree[m] == 0 {
				freed = append(freed, m)
			}
		}
		if len(freed) > 0 {
			sort.Strings(freed)
			ready = mergeSorted(ready, freed)
		}
	}

	if len(out) != len(g.nodes) {
		return out, ErrCycle
	}
	return out, nil
}

// CycleNodes returns the nodes that could not be ordered — i.e. those on or
// downstream of a cycle — in lexicographic order. Empty when the graph is a DAG.
func (g *Graph) CycleNodes() []string {
	done, err := g.Sort()
	if err == nil {
		return []string{}
	}
	placed := map[string]bool{}
	for _, n := range done {
		placed[n] = true
	}
	stuck := []string{}
	for _, n := range g.nodes {
		if !placed[n] {
			stuck = append(stuck, n)
		}
	}
	return stuck
}

// mergeSorted merges two sorted string slices into one sorted slice.
func mergeSorted(a, b []string) []string {
	out := make([]string, 0, len(a)+len(b))
	i, j := 0, 0
	for i < len(a) && j < len(b) {
		if a[i] <= b[j] {
			out = append(out, a[i])
			i++
		} else {
			out = append(out, b[j])
			j++
		}
	}
	out = append(out, a[i:]...)
	out = append(out, b[j:]...)
	return out
}

// FromPairs builds a Graph from "node depends on dep" pairs. Each pair is
// {node, dep}. Handy for tests and literal declarations.
func FromPairs(pairs [][2]string) *Graph {
	g := New()
	for _, p := range pairs {
		g.DependOn(p[0], p[1])
	}
	return g
}

// String renders the graph as "node <- dep1, dep2" lines, sorted. Useful for
// debugging and for demos.
func (g *Graph) String() string {
	var b strings.Builder
	for _, n := range g.nodes {
		b.WriteString(n)
		if d := g.deps[n]; len(d) > 0 {
			b.WriteString(" <- ")
			b.WriteString(strings.Join(d, ", "))
		}
		b.WriteString("\n")
	}
	return b.String()
}
