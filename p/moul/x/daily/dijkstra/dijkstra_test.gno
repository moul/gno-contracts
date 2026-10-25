package dijkstra

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// roads is the worked example used by most of the tests below, small enough to
// solve by hand. It is directed, and it is built so that the obvious answers
// are both wrong: the direct a -> c arc of 4 loses to a -> b -> c at 3, and c
// is the first node to offer a route to e (at 9) but d supplies a cheaper one
// (8) two steps later.
//
//	a -2-> b   a -4-> c   b -1-> c   b -3-> d   c -6-> e   d -3-> e
//
// f is an island: nothing reaches it, and it reaches nothing.
func roads() *Graph {
	g := New()
	g.AddEdge("a", "b", 2)
	g.AddEdge("a", "c", 4)
	g.AddEdge("b", "c", 1)
	g.AddEdge("b", "d", 3)
	g.AddEdge("c", "e", 6)
	g.AddEdge("d", "e", 3)
	g.AddNode("f")
	return g
}

func TestDistances(t *testing.T) {
	r := roads().From("a")

	tests := []struct {
		node string
		want int
		ok   bool
	}{
		{"a", 0, true},
		{"b", 2, true},
		{"c", 3, true}, // via b, not the direct arc of 4
		{"d", 5, true},
		{"e", 8, true}, // a,b,d,e at 8 beats a,b,c,e at 9
		{"f", Unreachable, false},
		{"nowhere", Unreachable, false},
	}
	for _, tt := range tests {
		got, ok := r.Dist(tt.node)
		uassert.Equal(t, tt.ok, ok, "ok for "+tt.node)
		uassert.Equal(t, tt.want, got, "dist for "+tt.node)
	}
}

func TestPaths(t *testing.T) {
	r := roads().From("a")

	tests := []struct {
		node string
		want string
	}{
		{"a", "a"},
		{"b", "a>b"},
		{"c", "a>b>c"},
		{"d", "a>b>d"},
		{"e", "a>b>d>e"},
		{"f", ""},
		{"nowhere", ""},
	}
	for _, tt := range tests {
		uassert.Equal(t, tt.want, r.PathString(tt.node, ">"), "path to "+tt.node)
	}

	uassert.Equal(t, 0, len(r.Path("f")), "unreachable path is nil")
	uassert.Equal(t, 1, len(r.Path("a")), "the source is a path of one")
}

// A node is settled in distance order, closest first, and that sequence is the
// algorithm. The island never settles at all.
func TestSettleOrder(t *testing.T) {
	r := roads().From("a")
	uassert.Equal(t, "a,b,c,d,e", strings.Join(r.Order(), ","))
	uassert.Equal(t, 5, r.Reachable())
	uassert.Equal(t, "a", r.Source())
}

// The tie-break is the property an on-chain Render depends on: two nodes at
// the same distance settle in the order they were added, never in map order,
// so the same graph gives the same answer on every validator.
func TestTiesSettleInInsertionOrder(t *testing.T) {
	g := New()
	for _, n := range []string{"hub", "west", "east", "north"} {
		g.AddNode(n)
	}
	g.AddEdge("hub", "west", 5)
	g.AddEdge("hub", "east", 5)
	g.AddEdge("hub", "north", 5)
	uassert.Equal(t, "hub,west,east,north", strings.Join(g.From("hub").Order(), ","))

	// Same graph, nodes declared in a different order: the settle order
	// follows the declaration, which is the whole claim.
	h := New()
	for _, n := range []string{"hub", "north", "east", "west"} {
		h.AddNode(n)
	}
	h.AddEdge("hub", "west", 5)
	h.AddEdge("hub", "east", 5)
	h.AddEdge("hub", "north", 5)
	uassert.Equal(t, "hub,north,east,west", strings.Join(h.From("hub").Order(), ","))
}

// An equal-cost route never displaces the incumbent, so the predecessor chain
// is the first one found rather than the last one tried.
func TestEqualCostKeepsTheFirstPredecessor(t *testing.T) {
	g := New()
	g.AddEdge("s", "left", 1)
	g.AddEdge("s", "right", 1)
	g.AddEdge("left", "t", 1)
	g.AddEdge("right", "t", 1)
	r := g.From("s")
	uassert.Equal(t, 2, mustDist(t, r, "t"))
	uassert.Equal(t, "s>left>t", r.PathString("t", ">"))

	via, ok := r.Via("t")
	uassert.True(t, ok)
	uassert.Equal(t, "left", via)

	_, ok = r.Via("s")
	uassert.False(t, ok, "the source has no predecessor")
}

// Parallel arcs are kept, and the search takes the cheapest of them.
func TestParallelArcsTakeTheCheapest(t *testing.T) {
	g := New()
	g.AddEdge("a", "b", 9)
	g.AddEdge("a", "b", 2)
	g.AddEdge("a", "b", 7)
	uassert.Equal(t, 3, g.Edges())
	uassert.Equal(t, 2, g.Len())
	uassert.Equal(t, 2, mustDist(t, g.From("a"), "b"))
}

func TestUndirectedGoesBothWays(t *testing.T) {
	g := New()
	g.AddUndirected("x", "y", 3)
	g.AddUndirected("y", "z", 4)
	uassert.Equal(t, 4, g.Edges(), "each undirected pair is two arcs")
	uassert.Equal(t, 7, mustDist(t, g.From("x"), "z"))
	uassert.Equal(t, 7, mustDist(t, g.From("z"), "x"))
}

// A zero-weight arc is legal and must not be mistaken for "no arc".
func TestZeroWeightArcs(t *testing.T) {
	g := New()
	g.AddEdge("a", "b", 0)
	g.AddEdge("b", "c", 0)
	r := g.From("a")
	uassert.Equal(t, 0, mustDist(t, r, "c"))
	uassert.Equal(t, "a>b>c", r.PathString("c", ">"))
}

// Relaxations counts improvements, not arcs looked at. On roads() the six
// arcs yield six improvements, but two of them are second thoughts: c drops
// from 4 to 3 once b settles, and e drops from 9 to 8 once d does.
func TestRelaxationsCountImprovements(t *testing.T) {
	uassert.Equal(t, 6, roads().From("a").Relaxations())
}

func TestGraphBookkeeping(t *testing.T) {
	g := roads()
	uassert.Equal(t, 6, g.Len())
	uassert.Equal(t, 6, g.Edges())
	uassert.Equal(t, "a,b,c,d,e,f", strings.Join(g.Names(), ","))
	uassert.True(t, g.Has("f"))
	uassert.False(t, g.Has("nowhere"))

	// AddNode is idempotent and returns the existing index.
	uassert.Equal(t, 0, g.AddNode("a"))
	uassert.Equal(t, 6, g.Len())

	// Names is a copy: reordering it must not reorder the graph.
	names := g.Names()
	names[0] = "mutated"
	uassert.Equal(t, "a", g.Names()[0])
}

// A search from an island reaches only itself, and that is not an error.
func TestSearchFromAnIsland(t *testing.T) {
	r := roads().From("f")
	uassert.Equal(t, 1, r.Reachable())
	uassert.Equal(t, "f", strings.Join(r.Order(), ","))
	uassert.Equal(t, 0, mustDist(t, r, "f"))
	_, ok := r.Dist("a")
	uassert.False(t, ok, "arcs are one-way, f reaches nothing")
}

// A Result is a snapshot. Adding arcs afterwards does not change what it says,
// which is what makes it safe to hold across a Render.
func TestResultIsASnapshot(t *testing.T) {
	g := New()
	g.AddEdge("a", "b", 10)
	r := g.From("a")
	g.AddEdge("a", "b", 1)
	uassert.Equal(t, 10, mustDist(t, r, "b"))
	uassert.Equal(t, 1, mustDist(t, g.From("a"), "b"))
}

// The preconditions are enforced at build time, where the caller can still do
// something about it, rather than silently returning a wrong shortest path.
func TestBuildPanics(cur realm, t *testing.T) {
	g := New()
	uassert.PanicsWithMessage(t, cur, "dijkstra: negative weight", func() { g.AddEdge("a", "b", -1) })
	uassert.PanicsWithMessage(t, cur, "dijkstra: self-loop", func() { g.AddEdge("a", "a", 1) })
	uassert.PanicsWithMessage(t, cur, "dijkstra: empty node name", func() { g.AddNode("") })
	uassert.PanicsWithMessage(t, cur, "dijkstra: unknown source: zz", func() { g.From("zz") })
	uassert.NotPanics(t, cur, func() { g.AddEdge("a", "b", 0) })
}

func TestCapacityPanics(cur realm, t *testing.T) {
	g := New()
	for i := 0; i < MaxNodes; i++ {
		g.AddNode(name(i))
	}
	uassert.Equal(t, MaxNodes, g.Len())
	uassert.PanicsWithMessage(t, cur, "dijkstra: too many nodes", func() { g.AddNode("one-too-many") })

	// Parallel arcs, so the edge cap is reached without tripping the node cap
	// first: MaxEdges is deliberately larger than MaxNodes.
	h := New()
	for i := 0; i < MaxEdges; i++ {
		h.AddEdge("hub", "spoke", 1)
	}
	uassert.Equal(t, MaxEdges, h.Edges())
	uassert.Equal(t, 2, h.Len())
	uassert.PanicsWithMessage(t, cur, "dijkstra: too many edges", func() { h.AddEdge("hub", "late", 1) })
}

// A long chain exercises the heap past the point where a linear scan would
// still look correct, and pins the cost at the same time.
func TestLongChain(t *testing.T) {
	g := New()
	for i := 0; i < 200; i++ {
		g.AddEdge(name(i), name(i+1), 2)
	}
	r := g.From(name(0))
	uassert.Equal(t, 400, mustDist(t, r, name(200)))
	uassert.Equal(t, 201, r.Reachable())
	uassert.Equal(t, 200, r.Relaxations(), "a chain improves each node exactly once")
	uassert.Equal(t, 201, len(r.Path(name(200))))
}

// mustDist fails the test rather than returning a zero that reads like a real
// distance.
func mustDist(t *testing.T, r *Result, node string) int {
	t.Helper()
	d, ok := r.Dist(node)
	if !ok {
		t.Fatalf("no route to %s", node)
	}
	return d
}

// name turns an index into a stable node name, so the generated graphs above
// do not depend on formatting helpers.
func name(i int) string {
	if i == 0 {
		return "n0"
	}
	var digits []byte
	for i > 0 {
		digits = append([]byte{byte('0' + i%10)}, digits...)
		i /= 10
	}
	return "n" + string(digits)
}
