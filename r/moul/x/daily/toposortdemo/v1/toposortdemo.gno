// Package toposortdemo is a small gnoweb demo of the dependency ordering
// provided by the [p/moul/x/daily/toposort](/p/moul/x/daily/toposort/v1)
// library: it shows a build graph resolved into a safe install order, and a
// deliberately broken graph to show how a cycle is reported.
//
// It contains no ordering logic of its own — the graph, the sort and the cycle
// detection all come from the library. Stateless and read-only, so Render is
// fully deterministic.
package toposortdemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/x/daily/toposort/v1"
)

// buildGraph is a small, realistic dependency graph: a realm on top of a couple
// of libraries, themselves on a shared core.
func buildGraph() *toposort.Graph {
	return toposort.FromPairs([][2]string{
		{"realm", "ui"},
		{"realm", "storage"},
		{"ui", "markdown"},
		{"storage", "avl"},
		{"markdown", "strings"},
		{"avl", "strings"},
	})
}

// cyclicGraph is broken on purpose: auth and session need each other.
func cyclicGraph() *toposort.Graph {
	return toposort.FromPairs([][2]string{
		{"server", "auth"},
		{"auth", "session"},
		{"session", "auth"},
	})
}

// Render renders the demo for gnoweb.
//
//	Render("")       / Render("/") -> the build graph, resolved
//	Render("/cycle")               -> the broken graph and its report
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# Topological Sort\n\n")
	b.WriteString("Ordering a dependency graph so nothing is built before what it needs, ")
	b.WriteString("demoing the [`p/moul/x/daily/toposort`](/p/moul/x/daily/toposort/v1) library.\n\n")

	if parseArg(path) == "cycle" {
		return b.String() + renderCycle()
	}

	g := buildGraph()
	b.WriteString("## The graph\n\n```\n")
	b.WriteString(g.String())
	b.WriteString("```\n\n")

	order, err := g.Sort()
	if err != nil {
		b.WriteString("_Unexpectedly cyclic._\n")
		return b.String()
	}
	b.WriteString("## Install order\n\n")
	for i, n := range order {
		b.WriteString(strconv.Itoa(i + 1))
		b.WriteString(". `")
		b.WriteString(n)
		b.WriteString("`\n")
	}
	b.WriteString("\nTies are broken lexicographically, so this ordering is the ")
	b.WriteString("*only* one the library will ever produce for this graph.\n\n")
	b.WriteString("> See [`/cycle`](/r/moul/x/daily/toposortdemo/v1:cycle) for what happens ")
	b.WriteString("when the graph is not a DAG.\n")
	return b.String()
}

// renderCycle shows the failure mode.
func renderCycle() string {
	g := cyclicGraph()
	var b strings.Builder
	b.WriteString("## A graph with a cycle\n\n```\n")
	b.WriteString(g.String())
	b.WriteString("```\n\n")

	order, err := g.Sort()
	if err == nil {
		b.WriteString("_Unexpectedly acyclic._\n")
		return b.String()
	}
	b.WriteString("`Sort` returns an error: **")
	b.WriteString(err.Error())
	b.WriteString("**\n\n")
	b.WriteString("Ordered before giving up: ")
	if len(order) == 0 {
		b.WriteString("_nothing_")
	} else {
		b.WriteString("`" + strings.Join(order, "`, `") + "`")
	}
	b.WriteString("\n\nStuck on the cycle: `")
	b.WriteString(strings.Join(g.CycleNodes(), "`, `"))
	b.WriteString("`\n\n> The nodes still stuck are named rather than silently dropped, ")
	b.WriteString("so a caller can report exactly which dependencies are tangled.\n")
	return b.String()
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
