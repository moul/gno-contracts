// Package bellmanforddemo is a small gnoweb demo of the shortest-path search
// provided by the [p/moul/x/daily/bellmanford](/p/moul/x/daily/bellmanford/v0)
// library: cheapest routes across a network where one hop pays a rebate, and
// the answer a routing table has to give when no cheapest route exists at all.
//
// It contains no search logic of its own. Stateless, so Render is
// deterministic: every figure below comes from the fixed graphs declared at
// the top of this file, never from chain state, which is what lets an example
// test pin the page.
package bellmanforddemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/x/daily/bellmanford/v0"
)

// link is one arc of a worked example.
type link struct {
	from, to string
	cost     int
}

// fees is a payment network with one rebate in it. The arc depot -> market
// pays 3 back, which is what makes the four-hop route to market cheaper than
// the one-hop arc of 4, and what moves depot's own best route too.
var fees = []link{
	{"gate", "hubA", 7},
	{"gate", "hubB", 2},
	{"gate", "market", 4},
	{"hubB", "hubA", 1},
	{"hubA", "depot", 2},
	{"hubB", "depot", 4},
	{"depot", "market", -3},
	{"market", "vault", 2},
}

// loop is the same shape with one arc changed: loopB -> loopC now pays more
// back than the rest of the ring costs, so going round it is free money and
// nothing downstream has a cheapest route any more.
var loop = []link{
	{"mint", "safe", 5},
	{"mint", "loopA", 1},
	{"loopA", "loopB", 2},
	{"loopB", "loopC", -4},
	{"loopC", "loopA", 1},
	{"loopC", "sink", 3},
}

const (
	feeSource  = "gate"
	loopSource = "mint"
	// isolated is in the fee graph with no arcs at all, to show that
	// unreachable is an answer rather than an error.
	isolated = "cold"
	// rebated names the arc the first section is about.
	rebated = "depot"
)

// Render renders the demo for gnoweb.
//
//	Render("") / Render("/") -> the full demo
func Render(path string) string {
	var b strings.Builder

	b.WriteString("# Bellman-Ford\n\n")
	b.WriteString("Cheapest routes across a graph whose arcs may cost less ")
	b.WriteString("than nothing, demoing the ")
	b.WriteString("[`p/moul/x/daily/bellmanford`](/p/moul/x/daily/bellmanford/v0) library.\n\n")

	g := build(fees)
	g.AddNode(isolated)
	r := g.From(feeSource)

	b.WriteString("## A fee table with a rebate in it\n\n")
	b.WriteString(strconv.Itoa(g.Len()) + " nodes, " + strconv.Itoa(g.Edges()))
	b.WriteString(" one-way arcs, priced from `" + feeSource + "`. One of them ")
	b.WriteString("is negative: `" + rebated + "` pays 3 back for sending on.\n\n")
	b.WriteString(arcTable(fees) + "\n")
	b.WriteString("`" + isolated + "` is in the graph with no arcs at all.\n\n")

	b.WriteString("## Cheapest route to each node\n\n")
	b.WriteString(routeTable(g, r) + "\n")
	b.WriteString("The two rows worth reading twice are `market` and `vault`. ")
	b.WriteString("`market` sits one arc from the source at a cost of 4, and ")
	b.WriteString("the cheapest way to it is the four-arc detour through the ")
	b.WriteString("rebate, at 2. A search that settles a node at its best ")
	b.WriteString("known cost and never looks at it again would have stopped ")
	b.WriteString("at 4, because `" + rebated + "` is only priced later, and ")
	b.WriteString("`vault` would have inherited the mistake.\n\n")

	b.WriteString("## What the rebate is worth\n\n")
	b.WriteString("The same network with that one arc priced at +3 instead, ")
	b.WriteString("so the detour is a detour and nothing else.\n\n")
	plain := g.From(feeSource)
	withoutRebate := build(repriced(fees, rebated, "market", 3))
	withoutRebate.AddNode(isolated)
	noRebate := withoutRebate.From(feeSource)
	ct := ui.NewTable("node", "with the rebate", "without it")
	for _, n := range g.Names() {
		ct.Row(ui.Cell(n), distCell(plain, n), distCell(noRebate, n))
	}
	b.WriteString(ct.String() + "\n")
	b.WriteString("One arc, two answers changed. That is the whole reason ")
	b.WriteString("to pay O(V*E) instead of O((V+E) log V).\n\n")

	b.WriteString("## How many passes it took\n\n")
	b.WriteString("The algorithm relaxes every arc, over and over, until a ")
	b.WriteString("pass changes nothing. A shortest path visits each node at ")
	b.WriteString("most once, so it is at most V-1 arcs long, and one pass ")
	b.WriteString("extends every known route by at least one arc.\n\n")
	pt := ui.NewTable("figure", "value", "meaning")
	pt.Row("nodes", strconv.Itoa(g.Len()), "V")
	pt.Row("arcs", strconv.Itoa(g.Edges()), "E")
	pt.Row("bound", strconv.Itoa(g.Len()-1), "V-1 passes, the worst case")
	pt.Row("passes made", strconv.Itoa(r.Rounds()), "it stopped as soon as a pass changed nothing")
	pt.Row("improvements", strconv.Itoa(r.Relaxations()), "arcs that actually lowered a distance")
	b.WriteString(pt.String() + "\n")
	b.WriteString("The passes figure is decided by the order the arcs were ")
	b.WriteString("added in, not by the graph, so it is the number to watch ")
	b.WriteString("when gas matters.\n\n")

	b.WriteString("## When there is no cheapest route at all\n\n")
	h := build(loop)
	hr := h.From(loopSource)
	b.WriteString("Change one price and the ring `loopA -> loopB -> loopC` ")
	b.WriteString("pays more back than it costs.\n\n")
	b.WriteString(arcTable(loop) + "\n")
	b.WriteString("Going round it once saves ")
	b.WriteString(strconv.Itoa(-hr.CycleWeight()))
	b.WriteString(", so going round it twice saves twice as much, and asking ")
	b.WriteString("for the cheapest route to anything it reaches has no ")
	b.WriteString("answer. The run says so instead of returning the total ")
	b.WriteString("after an arbitrary number of turns:\n\n")
	st := ui.NewTable("node", "state", "distance", "route")
	for _, n := range h.Names() {
		st.Row(ui.Cell(n), hr.State(n).String(), distCell(hr, n), route(hr.Path(n)))
	}
	b.WriteString(st.String() + "\n")
	ct2 := ui.NewTable("what the run found", "value")
	ct2.Row("the cycle", route(hr.Cycle()))
	ct2.Row("one turn costs", strconv.Itoa(hr.CycleWeight()))
	ct2.Row("nodes it poisons", names(hr.UnboundedNodes()))
	b.WriteString(ct2.String() + "\n")
	b.WriteString("`" + loopSource + "` and `safe` keep real distances: the ")
	b.WriteString("cycle cannot reach them, so nothing it does changes what ")
	b.WriteString("they are worth. Reporting the blast radius rather than ")
	b.WriteString("failing the whole query is the difference between a fee ")
	b.WriteString("table a realm can act on and one it has to throw away.\n\n")

	b.WriteString("## What it will not do\n\n")
	lt := ui.NewTable("limit", "value", "why")
	lt.Row("`MaxNodes`", strconv.Itoa(bellmanford.MaxNodes), "V bounds the pass count")
	lt.Row("`MaxEdges`", strconv.Itoa(bellmanford.MaxEdges), "E bounds the work per pass")
	lt.Row("`MaxWeight`", strconv.Itoa(bellmanford.MaxWeight), "V times this is the largest total, well inside an int")
	lt.Row("unknown source", "panics", "a typo must not read as \"nothing is reachable\"")
	lt.Row("negative cycle", "reported", "it is an answer, not an error")
	b.WriteString(lt.String() + "\n")
	b.WriteString("There is no unreachable sentinel on `Dist`, and there ")
	b.WriteString("cannot be: a negative total is a legitimate answer here, ")
	b.WriteString("so every value it could reserve is one a real route might ")
	b.WriteString("have. Ask `State` when the reason matters.\n")

	return b.String()
}

// build turns a link list into a graph, arcs in declaration order, which is
// also the order the search relaxes them in.
func build(links []link) *bellmanford.Graph {
	g := bellmanford.New()
	for _, l := range links {
		g.AddEdge(l.from, l.to, l.cost)
	}
	return g
}

// repriced copies a link list with one arc's cost replaced, so the two runs
// above differ by exactly that arc and nothing else.
func repriced(links []link, from, to string, cost int) []link {
	out := make([]link, len(links))
	for i, l := range links {
		out[i] = l
		if l.from == from && l.to == to {
			out[i].cost = cost
		}
	}
	return out
}

// arcTable renders a link list.
func arcTable(links []link) string {
	t := ui.NewTable("from", "to", "cost")
	for _, l := range links {
		t.Row(ui.Cell(l.from), ui.Cell(l.to), strconv.Itoa(l.cost))
	}
	return t.String()
}

// routeTable renders one run: what each node is worth and how it is reached.
func routeTable(g *bellmanford.Graph, r *bellmanford.Result) string {
	t := ui.NewTable("node", "state", "distance", "arrives via", "route")
	for _, n := range g.Names() {
		via, hasVia := r.Via(n)
		if !hasVia && r.State(n) == bellmanford.Settled {
			via = "source"
		}
		t.Row(ui.Cell(n), r.State(n).String(), distCell(r, n), ui.Cell(via), route(r.Path(n)))
	}
	return t.String()
}

// distCell renders a distance, or the state when there is no distance to
// render. A blank cell would read like zero, which is a real distance here.
func distCell(r *bellmanford.Result, node string) string {
	d, ok := r.Dist(node)
	if !ok {
		return r.State(node).String()
	}
	return strconv.Itoa(d)
}

// route joins a path with an arrow. Each node name is escaped on its own and
// the separator never is: running the whole joined string through the escaper
// would turn the arrows into a literal backslash soup.
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

// names renders a node list as a comma-separated cell, escaped the same way.
func names(in []string) string {
	if len(in) == 0 {
		return ""
	}
	cells := make([]string, len(in))
	for i, n := range in {
		cells[i] = ui.Cell(n)
	}
	return strings.Join(cells, ", ")
}
