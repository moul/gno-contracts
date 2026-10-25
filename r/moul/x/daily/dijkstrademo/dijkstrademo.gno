// Package dijkstrademo is a small gnoweb demo of the shortest-path search
// provided by the [p/moul/x/daily/dijkstra](/p/moul/x/daily/dijkstra/v0)
// library: the cheapest route to every node, the order the search settles
// them in, and the tie-break that makes both reproducible.
//
// It contains no search logic of its own. Stateless, so Render is
// deterministic: every figure below comes from the fixed graphs declared at
// the top of this file, never from chain state, which is what lets an example
// test pin the page.
package dijkstrademo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/x/daily/dijkstra/v0"
)

// link is one arc of the worked example: a small directed delivery network
// where the obvious route is the wrong one twice over.
type link struct {
	from, to string
	cost     int
}

var network = []link{
	{"depot", "north", 2},
	{"depot", "east", 4},
	{"north", "east", 1},
	{"north", "ridge", 3},
	{"east", "port", 6},
	{"ridge", "port", 3},
	{"port", "beacon", 2},
}

// The source of the worked example, and a node nothing reaches, to show that
// unreachable is an answer rather than an error.
const (
	source   = "depot"
	isolated = "quarry"
)

// fanout is the determinism example: one hub, three spokes, all at the same
// cost. Which one settles first is decided by the order they were declared
// in, never by a map.
var fanout = []string{"west", "south", "crater"}

// Render renders the demo for gnoweb.
//
//	Render("") / Render("/") -> the full demo
func Render(path string) string {
	var b strings.Builder

	b.WriteString("# Dijkstra\n\n")
	b.WriteString("The cheapest route from one node to every other node of a ")
	b.WriteString("weighted graph, demoing the ")
	b.WriteString("[`p/moul/x/daily/dijkstra`](/p/moul/x/daily/dijkstra/v0) library.\n\n")

	g := dijkstra.New()
	for _, l := range network {
		g.AddEdge(l.from, l.to, l.cost)
	}
	g.AddNode(isolated)
	r := g.From(source)

	b.WriteString("## The network\n\n")
	b.WriteString("Arcs are one-way. ")
	b.WriteString(strconv.Itoa(g.Len()) + " nodes, " + strconv.Itoa(g.Edges()))
	b.WriteString(" arcs, searched from `" + source + "`.\n\n")
	nt := ui.NewTable("from", "to", "cost")
	for _, l := range network {
		nt.Row(ui.Cell(l.from), ui.Cell(l.to), strconv.Itoa(l.cost))
	}
	b.WriteString(nt.String() + "\n")
	b.WriteString("`" + isolated + "` is in the graph with no arcs at all.\n\n")

	b.WriteString("## Cheapest route to each node\n\n")
	rt := ui.NewTable("node", "distance", "arrives via", "route")
	for _, n := range g.Names() {
		d, ok := r.Dist(n)
		if !ok {
			rt.Row(ui.Cell(n), "unreachable", "", "")
			continue
		}
		via, hasVia := r.Via(n)
		if !hasVia {
			via = "source"
		}
		rt.Row(ui.Cell(n), strconv.Itoa(d), ui.Cell(via), route(r.Path(n)))
	}
	b.WriteString(rt.String() + "\n")
	b.WriteString("Two of those rows are the point of the algorithm. `east` is ")
	b.WriteString("reachable directly for 4, and the answer is 3, through ")
	b.WriteString("`north`. `port` is first offered at 9 by `east`, and ends at ")
	b.WriteString("8 through `ridge`, which the search only discovers two ")
	b.WriteString("settlements later.\n\n")

	b.WriteString("## The order the search settles nodes\n\n")
	b.WriteString("Always the closest node still outstanding, never the next ")
	b.WriteString("one along an arc. That is the whole difference from a ")
	b.WriteString("breadth-first walk, and it is why a cheap long way round ")
	b.WriteString("still wins.\n\n")
	ot := ui.NewTable("step", "settles", "at distance")
	for i, n := range r.Order() {
		d, _ := r.Dist(n)
		ot.Row(strconv.Itoa(i+1), ui.Cell(n), strconv.Itoa(d))
	}
	b.WriteString(ot.String() + "\n")
	b.WriteString(strconv.Itoa(r.Reachable()) + " of " + strconv.Itoa(g.Len()))
	b.WriteString(" nodes were reached, in " + strconv.Itoa(r.Relaxations()))
	b.WriteString(" improvements. An arc that is looked at and rejected costs ")
	b.WriteString("a comparison; only an improvement costs a write.\n\n")

	b.WriteString("## Ties, and why a realm should care\n\n")
	b.WriteString("Three spokes, all 5 away from the hub. Nothing in the ")
	b.WriteString("distances separates them, so something else has to, and ")
	b.WriteString("that something must not be map iteration order: a `Render` ")
	b.WriteString("that reshuffled between validating nodes would be a ")
	b.WriteString("consensus bug, not a cosmetic one.\n\n")
	tt := ui.NewTable("declared", "settle order")
	tt.Row(names(fanout), route(settleFanout(fanout)))
	reversed := reverse(fanout)
	tt.Row(names(reversed), route(settleFanout(reversed)))
	b.WriteString(tt.String() + "\n")
	b.WriteString("The tie resolves to the order the graph was built in, and ")
	b.WriteString("nothing else. Build it the same way twice and you get the ")
	b.WriteString("same page twice.\n\n")

	b.WriteString("## What it will not do\n\n")
	b.WriteString("A negative arc panics at `AddEdge`, where the caller can ")
	b.WriteString("still fix it. Accepting one would not return an error ")
	b.WriteString("later, it would return a confident wrong answer: the ")
	b.WriteString("search never revisits a settled node, so a negative arc ")
	b.WriteString("pointing back at one is simply never seen.\n\n")
	lt := ui.NewTable("limit", "value", "why")
	lt.Row("`MaxNodes`", strconv.Itoa(dijkstra.MaxNodes),
		"the frontier holds at most one entry per node, so this bounds memory")
	lt.Row("`MaxEdges`", strconv.Itoa(dijkstra.MaxEdges),
		"arcs bound the work, not the memory")
	lt.Row("negative arc", "panics", "the algorithm's precondition, not a simplification")
	lt.Row("self-loop", "panics", "it can never shorten a path, so it is a caller mistake")
	b.WriteString(lt.String() + "\n")
	b.WriteString("Both caps are small on purpose. This is a routing table ")
	b.WriteString("for a realm, not a road atlas, and a caller that can state ")
	b.WriteString("the worst case up front can price the gas before it sends ")
	b.WriteString("the transaction.\n")

	return b.String()
}

// route joins a path with an arrow. Each node name is escaped on its own and
// the separator never is: running the whole joined string through the
// escaper would turn the arrows into a literal backslash soup, which is the
// bug this spelling exists to avoid.
func route(path []string) string {
	if len(path) == 0 {
		return ""
	}
	cells := make([]string, len(path))
	for i, n := range path {
		cells[i] = ui.Cell(n)
	}
	return strings.Join(cells, " -> ")
}

// names renders a declaration order as a comma-separated list, escaped the
// same way.
func names(in []string) string {
	cells := make([]string, len(in))
	for i, n := range in {
		cells[i] = ui.Cell(n)
	}
	return strings.Join(cells, ", ")
}

// settleFanout builds the hub-and-spoke graph with the spokes declared in the
// given order and returns the order the search settles them in.
func settleFanout(spokes []string) []string {
	g := dijkstra.New()
	g.AddNode("hub")
	for _, s := range spokes {
		g.AddNode(s)
	}
	for _, s := range spokes {
		g.AddEdge("hub", s, 5)
	}
	return g.From("hub").Order()
}

// reverse copies a slice back to front. Written out rather than imported
// because there is no sensible shared home for three lines of it.
func reverse(in []string) []string {
	out := make([]string, len(in))
	for i, s := range in {
		out[len(in)-1-i] = s
	}
	return out
}
