package bellmanford

import (
	"strconv"
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// fees is the worked example: a payment network where one hop pays a rebate.
// It is built so that a greedy settle-and-never-revisit search gets two of the
// answers wrong.
//
//	gate -7-> hubA    gate -2-> hubB    gate -4-> market
//	hubB -1-> hubA    hubA -2-> depot   hubB -4-> depot
//	depot --3-> market (a rebate)       market -2-> vault
//
// cold is an island: nothing reaches it and it reaches nothing.
func fees() *Graph {
	g := New()
	g.AddEdge("gate", "hubA", 7)
	g.AddEdge("gate", "hubB", 2)
	g.AddEdge("gate", "market", 4)
	g.AddEdge("hubB", "hubA", 1)
	g.AddEdge("hubA", "depot", 2)
	g.AddEdge("hubB", "depot", 4)
	g.AddEdge("depot", "market", -3)
	g.AddEdge("market", "vault", 2)
	g.AddNode("cold")
	return g
}

// loop is the negative cycle example. loopA -> loopB -> loopC -> loopA costs
// -1 per turn, sink hangs off the cycle, and safe hangs off the source where
// no amount of looping can reach it.
func loop() *Graph {
	g := New()
	g.AddEdge("mint", "loopA", 1)
	g.AddEdge("loopA", "loopB", 2)
	g.AddEdge("loopB", "loopC", -4)
	g.AddEdge("loopC", "loopA", 1)
	g.AddEdge("loopC", "sink", 3)
	g.AddEdge("mint", "safe", 5)
	return g
}

func TestDistances(t *testing.T) {
	r := fees().From("gate")

	tests := []struct {
		node string
		want int
		ok   bool
	}{
		{"gate", 0, true},
		{"hubB", 2, true},
		{"hubA", 3, true},   // 2+1 through hubB, not the direct arc of 7
		{"depot", 5, true},  // 3+2 through hubA, not 2+4 through hubB
		{"market", 2, true}, // 5-3 through the rebate, not the direct arc of 4
		{"vault", 4, true},
		{"cold", 0, false},
		{"nowhere", 0, false},
	}
	for _, tt := range tests {
		got, ok := r.Dist(tt.node)
		uassert.Equal(t, tt.ok, ok, "ok for "+tt.node)
		uassert.Equal(t, tt.want, got, "dist for "+tt.node)
	}
	uassert.Equal(t, "gate", r.Source())
	uassert.Equal(t, 6, r.Reachable(), "every node but cold")
	uassert.False(t, r.HasNegativeCycle())
}

// The rebate is the whole point: the cheapest route to market is four hops
// long and the direct arc is one hop.
func TestPathsTakeTheRebate(t *testing.T) {
	r := fees().From("gate")

	tests := []struct {
		node string
		want string
	}{
		{"gate", "gate"},
		{"hubA", "gate>hubB>hubA"},
		{"depot", "gate>hubB>hubA>depot"},
		{"market", "gate>hubB>hubA>depot>market"},
		{"vault", "gate>hubB>hubA>depot>market>vault"},
		{"cold", ""},
		{"nowhere", ""},
	}
	for _, tt := range tests {
		uassert.Equal(t, tt.want, r.PathString(tt.node, ">"), "path to "+tt.node)
	}

	via, ok := r.Via("market")
	uassert.True(t, ok)
	uassert.Equal(t, "depot", via)
	_, ok = r.Via("gate")
	uassert.False(t, ok, "the source has no predecessor")
}

// A distance below zero is a legitimate answer here, which is why Dist has no
// sentinel: the int that comes back with ok=false means nothing at all.
func TestNegativeDistancesAreLegitimate(t *testing.T) {
	g := New()
	g.AddEdge("a", "b", -5)
	g.AddEdge("b", "c", 1)
	r := g.From("a")
	uassert.Equal(t, -5, mustDist(t, r, "b"))
	uassert.Equal(t, -4, mustDist(t, r, "c"))
	uassert.Equal(t, Settled.String(), r.State("b").String())
}

func TestNegativeCycleIsReported(t *testing.T) {
	r := loop().From("mint")

	uassert.True(t, r.HasNegativeCycle())
	cycle := r.Cycle()
	uassert.Equal(t, 4, len(cycle), "three nodes, the first repeated to close it")
	uassert.Equal(t, cycle[0], cycle[len(cycle)-1], "the walk closes")
	uassert.Equal(t, "loopA,loopB,loopC", sortedUnique(cycle))
	uassert.Equal(t, -1, r.CycleWeight())
	uassert.True(t, r.CycleWeight() < 0, "a reported cycle is always negative")
}

// A node a negative cycle can reach has no shortest path, and saying so is the
// difference between this package and one that returns a confident number.
func TestNegativeCyclePoisonsOnlyWhatItReaches(t *testing.T) {
	r := loop().From("mint")

	tests := []struct {
		node string
		want State
	}{
		{"mint", Settled},
		{"safe", Settled},
		{"loopA", Unbounded},
		{"loopB", Unbounded},
		{"loopC", Unbounded},
		{"sink", Unbounded},
		{"nowhere", Unknown},
	}
	for _, tt := range tests {
		uassert.Equal(t, tt.want.String(), r.State(tt.node).String(), "state of "+tt.node)
	}

	uassert.Equal(t, 5, mustDist(t, r, "safe"), "the cycle cannot reach safe")
	_, ok := r.Dist("sink")
	uassert.False(t, ok, "no shortest path exists, so there is no number to give")
	uassert.Equal(t, "", r.PathString("sink", ">"), "and no path either")
	uassert.Equal(t, "loopA,loopB,loopC,sink", strings.Join(r.UnboundedNodes(), ","))
}

// The smallest negative cycle is one arc long, and refusing self-loops would
// have hidden it rather than simplified anything.
func TestNegativeSelfLoopIsTheSmallestCycle(t *testing.T) {
	g := New()
	g.AddEdge("a", "a", -2)
	r := g.From("a")
	uassert.True(t, r.HasNegativeCycle())
	uassert.Equal(t, "a>a", strings.Join(r.Cycle(), ">"))
	uassert.Equal(t, -2, r.CycleWeight())
	uassert.Equal(t, Unbounded.String(), r.State("a").String())

	// A non-negative self-loop is harmless: it can never improve anything.
	h := New()
	h.AddEdge("a", "a", 3)
	h.AddEdge("a", "b", 1)
	hr := h.From("a")
	uassert.False(t, hr.HasNegativeCycle())
	uassert.Equal(t, 1, mustDist(t, hr, "b"))
	uassert.Equal(t, 0, len(hr.Cycle()))
}

// An unreachable negative cycle is not this run's problem. The source cannot
// reach it, so every distance the run reports is a real shortest path.
func TestUnreachableNegativeCycleIsNotReported(t *testing.T) {
	g := New()
	g.AddEdge("s", "t", 1)
	g.AddEdge("x", "y", -1)
	g.AddEdge("y", "x", -1)
	r := g.From("s")
	uassert.False(t, r.HasNegativeCycle())
	uassert.Equal(t, 1, mustDist(t, r, "t"))
	uassert.Equal(t, Unreached.String(), r.State("x").String())
}

// Rounds is the honest cost figure: the bound is V-1 passes, and the run stops
// as soon as a pass changes nothing. Arc order decides how many it needs.
func TestRoundsStopEarly(t *testing.T) {
	forward := New()
	backward := New()
	const hops = 12
	for i := 0; i < hops; i++ {
		forward.AddEdge(name(i), name(i+1), 1)
	}
	for i := hops - 1; i >= 0; i-- {
		backward.AddEdge(name(i), name(i+1), 1)
	}

	f := forward.From(name(0))
	uassert.Equal(t, hops, mustDist(t, f, name(hops)))
	uassert.Equal(t, 2, f.Rounds(), "one pass solves it, the second proves it")
	uassert.Equal(t, hops, f.Relaxations())

	b := backward.From(name(0))
	uassert.Equal(t, hops, mustDist(t, b, name(hops)))
	uassert.Equal(t, hops, b.Rounds(), "the worst order needs a pass per hop, which is the V-1 bound")
	uassert.Equal(t, f.Relaxations(), b.Relaxations(), "the same improvements, bought with six times the passes")
	uassert.False(t, b.HasNegativeCycle(), "hitting the bound is not a cycle, and the extra pass proves it")
}

// A Result is a snapshot. Adding arcs afterwards does not change what it says,
// which is what makes it safe to compute once and hold across a Render.
func TestResultIsASnapshot(t *testing.T) {
	g := New()
	g.AddEdge("a", "b", 10)
	r := g.From("a")
	g.AddEdge("a", "b", 1)
	uassert.Equal(t, 10, mustDist(t, r, "b"))
	uassert.Equal(t, 1, mustDist(t, g.From("a"), "b"))
}

// Parallel arcs are kept rather than collapsed, and the search takes the
// cheapest of them whichever way round they were declared.
func TestParallelArcsTakeTheCheapest(t *testing.T) {
	g := New()
	g.AddEdge("a", "b", 5)
	g.AddEdge("a", "b", -2)
	g.AddEdge("a", "b", 3)
	uassert.Equal(t, 3, g.Edges())
	uassert.Equal(t, 2, g.Len())
	uassert.Equal(t, -2, mustDist(t, g.From("a"), "b"))
}

func TestGraphBookkeeping(t *testing.T) {
	g := fees()
	uassert.Equal(t, 7, g.Len())
	uassert.Equal(t, 8, g.Edges())
	uassert.Equal(t, "gate,hubA,hubB,market,depot,vault,cold", strings.Join(g.Names(), ","))
	uassert.True(t, g.Has("cold"))
	uassert.False(t, g.Has("nowhere"))

	// AddNode is idempotent and returns the existing index.
	uassert.Equal(t, 0, g.AddNode("gate"))
	uassert.Equal(t, 7, g.Len())

	// Names is a copy: reordering it must not reorder the graph.
	names := g.Names()
	names[0] = "mutated"
	uassert.Equal(t, "gate", g.Names()[0])
}

// A search from an island reaches only itself, and that is not an error.
func TestSearchFromAnIsland(t *testing.T) {
	r := fees().From("cold")
	uassert.Equal(t, 1, r.Reachable())
	uassert.Equal(t, 0, mustDist(t, r, "cold"))
	uassert.Equal(t, Unreached.String(), r.State("gate").String())
}

// The preconditions are enforced at build time, where the caller can still do
// something about it.
func TestBuildPanics(cur realm, t *testing.T) {
	g := New()
	uassert.PanicsWithMessage(t, cur, "bellmanford: empty node name", func() { g.AddNode("") })
	uassert.PanicsWithMessage(t, cur, "bellmanford: weight out of range", func() { g.AddEdge("a", "b", MaxWeight+1) })
	uassert.PanicsWithMessage(t, cur, "bellmanford: weight out of range", func() { g.AddEdge("a", "b", -MaxWeight-1) })
	uassert.PanicsWithMessage(t, cur, "bellmanford: unknown source: zz", func() { g.From("zz") })
	uassert.NotPanics(t, cur, func() { g.AddEdge("a", "b", -MaxWeight) })
	uassert.NotPanics(t, cur, func() { g.AddEdge("a", "a", -1) })
}

func TestCapacityPanics(cur realm, t *testing.T) {
	g := New()
	for i := 0; i < MaxNodes; i++ {
		g.AddNode(name(i))
	}
	uassert.Equal(t, MaxNodes, g.Len())
	uassert.PanicsWithMessage(t, cur, "bellmanford: too many nodes", func() { g.AddNode("one-too-many") })

	// Parallel arcs, so the edge cap is reached without tripping the node cap
	// first: MaxEdges is deliberately larger than MaxNodes.
	h := New()
	for i := 0; i < MaxEdges; i++ {
		h.AddEdge("hub", "spoke", 1)
	}
	uassert.Equal(t, MaxEdges, h.Edges())
	uassert.PanicsWithMessage(t, cur, "bellmanford: too many edges", func() { h.AddEdge("hub", "late", 1) })
}

func TestStateStrings(t *testing.T) {
	uassert.Equal(t, "unknown", Unknown.String())
	uassert.Equal(t, "unreached", Unreached.String())
	uassert.Equal(t, "settled", Settled.String())
	uassert.Equal(t, "unbounded", Unbounded.String())
	uassert.Equal(t, "invalid", State(42).String())
}

// mustDist fails the test rather than returning a zero that reads like a real
// distance. Here that matters more than usual: zero is a plausible distance
// and Dist has no sentinel to return instead.
func mustDist(t *testing.T, r *Result, node string) int {
	t.Helper()
	d, ok := r.Dist(node)
	if !ok {
		t.Fatalf("no shortest path to %s", node)
	}
	return d
}

// name builds a stable node name from an index, zero padded so that the names
// sort the way the numbers do.
func name(i int) string {
	s := strconv.Itoa(i)
	for len(s) < 4 {
		s = "0" + s
	}
	return "n" + s
}

// sortedUnique joins the distinct members of a closed walk, in order, so a
// test can name the cycle without pinning which node the walk starts at.
func sortedUnique(walk []string) string {
	seen := map[string]bool{}
	var out []string
	for _, n := range walk {
		if seen[n] {
			continue
		}
		seen[n] = true
		out = append(out, n)
	}
	sortStrings(out)
	return strings.Join(out, ",")
}

// sortStrings is an insertion sort: gno has no sort.Slice and the lists here
// are three elements long.
func sortStrings(in []string) {
	for i := 1; i < len(in); i++ {
		for j := i; j > 0 && in[j] < in[j-1]; j-- {
			in[j], in[j-1] = in[j-1], in[j]
		}
	}
}
