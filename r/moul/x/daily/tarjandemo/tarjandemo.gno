// Package tarjandemo is a small gnoweb demo of the strongly connected
// components found by the [p/moul/x/daily/tarjan](/p/moul/x/daily/tarjan/v0)
// library: it shows an import graph with two tangles in it, and the same graph
// with one edge removed so that every tangle disappears.
//
// It contains no graph logic of its own. Stateless and read-only, so Render is
// fully deterministic.
package tarjandemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/x/daily/tarjan/v0"
)

// importGraph is a package import graph with two knots in it: auth and session
// need each other, and render/widget/theme go round in a three-way loop.
func importGraph() *tarjan.Graph {
	return tarjan.FromPairs([][2]string{
		{"app", "auth"},
		{"app", "render"},
		{"auth", "session"},
		{"session", "auth"},
		{"session", "store"},
		{"render", "widget"},
		{"widget", "theme"},
		{"theme", "render"},
		{"widget", "store"},
		{"store", "codec"},
	})
}

// cut is one edge removed from the graph on the /fixed page.
type cut struct{ from, to string }

// cuts are the two back edges, one per knot: each is the single edge that
// closes its own loop.
var cuts = []cut{
	{"session", "auth"},
	{"theme", "render"},
}

// untangled rebuilds the import graph without the two back edges, going
// through the library's own Nodes and Successors so the demo never keeps a
// second copy of the graph.
func untangled() *tarjan.Graph {
	g := importGraph()
	out := tarjan.New()
	for _, n := range g.Nodes() {
		out.Add(n)
		for _, s := range g.Successors(n) {
			if isCut(n, s) {
				continue
			}
			out.Edge(n, s)
		}
	}
	return out
}

// isCut reports whether an edge is one of the two removed on /fixed.
func isCut(from, to string) bool {
	for _, c := range cuts {
		if c.from == from && c.to == to {
			return true
		}
	}
	return false
}

// Render renders the demo for gnoweb.
//
//	Render("")        / Render("/") -> the import graph and its components
//	Render("/fixed")                -> the same graph with the back edges removed
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# Strongly Connected Components\n\n")
	b.WriteString("Finding which packages are tangled together, not just whether something is, ")
	b.WriteString("demoing the [`p/moul/x/daily/tarjan`](/p/moul/x/daily/tarjan/v0) library.\n\n")

	if parseArg(path) == "fixed" {
		g := untangled()
		return b.String() + renderGraph(g) + fixedNotes(g)
	}
	g := importGraph()
	return b.String() + renderGraph(g) + tangledNotes(g)
}

// renderGraph prints the adjacency list and the components, leaving the closing
// note to the caller.
func renderGraph(g *tarjan.Graph) string {
	var b strings.Builder
	b.WriteString("## The graph\n\n```\n")
	b.WriteString(g.String())
	b.WriteString("```\n\n")

	comps := g.Components()
	b.WriteString("## Components\n\n")
	for i, c := range comps {
		b.WriteString(strconv.Itoa(i + 1))
		b.WriteString(". `")
		b.WriteString(strings.Join(c, "`, `"))
		b.WriteString("`")
		if len(c) > 1 {
			b.WriteString(" **(tangled)**")
		}
		b.WriteString("\n")
	}
	b.WriteString("\n")
	return b.String()
}

// tangledNotes names the knots on the root page.
func tangledNotes(g *tarjan.Graph) string {
	var b strings.Builder
	b.WriteString("Two groups came back with more than one member, and those are the cycles:\n\n")
	for _, c := range g.Components() {
		if len(c) > 1 {
			b.WriteString("- `")
			b.WriteString(strings.Join(c, "` <-> `"))
			b.WriteString("`\n")
		}
	}
	b.WriteString("\nEverything else is alone in its own component, which is what an ordinary ")
	b.WriteString("acyclic package looks like. The list is in reverse topological order: ")
	b.WriteString("nothing can reach anything listed above it, so reading it top to bottom ")
	b.WriteString("is a safe build order, treating each tangle as one unit.\n\n")
	b.WriteString("> Drop one back edge per knot and both come apart: see ")
	b.WriteString("[`/fixed`](/r/moul/x/daily/tarjandemo/v0:fixed).\n")
	return b.String()
}

// fixedNotes states the result on the repaired page.
func fixedNotes(g *tarjan.Graph) string {
	if g.Cyclic() {
		return "_Unexpectedly still cyclic._\n"
	}
	return "Removing `session -> auth` and `theme -> render`, one back edge per knot, " +
		"left every component holding exactly one node, which is what an acyclic graph " +
		"looks like through this lens. The node list is unchanged and so is every other " +
		"edge: a cycle is a property of the edges that close it, not of the packages in " +
		"it.\n"
}

// parseArg extracts the first path segment.
func parseArg(path string) string {
	s := strings.TrimSpace(path)
	s = strings.TrimPrefix(s, "/")
	if i := strings.IndexByte(s, '/'); i >= 0 {
		s = s[:i]
	}
	return s
}
