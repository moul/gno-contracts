package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

// assetsDir holds generated, committed artifacts, mirroring pkgpath:
//
//	_assets/gno.land/r/moul/hello/v1/deps.{dot,svg,png}
//	_assets/graph.{dot,svg,png}            (whole-repo graph)
const assetsDir = "_assets"

// cmdGraph writes a deterministic dependency-graph .dot for every contract and a
// global one, then renders .svg/.png — but ONLY when the .dot actually changed
// (the .dot is the source of truth; committing it means renders are stable and
// don't churn on graphviz version differences). Rendering needs `dot` in PATH;
// without it, only the .dot files are written (CI renders them).
func cmdGraph(root string) error {
	m, err := loadManifest(root)
	if err != nil {
		return err
	}
	haveDot := false
	if _, err := exec.LookPath("dot"); err == nil {
		haveDot = true
	}
	changed, rendered, failed := 0, 0, 0

	render := func(dotRel string, dotChanged bool) error {
		base := strings.TrimSuffix(dotRel, ".dot")
		svg := filepath.Join(root, base+".svg")
		png := filepath.Join(root, base+".png")
		if !haveDot {
			return nil
		}
		// (re)render when the .dot changed or an output is missing
		if !dotChanged && fileExists(svg) && fileExists(png) {
			return nil
		}
		dot := filepath.Join(root, dotRel)
		// Resilient: a single failed render must not abort the whole run — the
		// .dot is still committed, and a later run (or the hourly self-heal) will
		// retry the missing svg/png. Report failures but keep going.
		if err := exec.Command("dot", "-Tsvg", dot, "-o", svg).Run(); err != nil {
			fmt.Fprintf(os.Stderr, "warning: render svg %s failed: %v (will retry next run)\n", dotRel, err)
			failed++
			return nil
		}
		if err := exec.Command("dot", "-Tpng", dot, "-o", png).Run(); err != nil {
			fmt.Fprintf(os.Stderr, "warning: render png %s failed: %v (will retry next run)\n", dotRel, err)
			failed++
			return nil
		}
		rendered++
		return nil
	}

	for _, c := range m.Contracts {
		rel := filepath.Join(assetsDir, filepath.FromSlash(c.PkgPath), "deps.dot")
		ch, err := writeIfChanged(filepath.Join(root, rel), perPkgDot(c))
		if err != nil {
			return err
		}
		if ch {
			changed++
		}
		if err := render(rel, ch); err != nil {
			return err
		}
	}

	// global graph
	grel := filepath.Join(assetsDir, "graph.dot")
	gch, err := writeIfChanged(filepath.Join(root, grel), globalDot(m))
	if err != nil {
		return err
	}
	if gch {
		changed++
	}
	if err := render(grel, gch); err != nil {
		return err
	}

	fmt.Printf("graph: %d dot changed, %d rendered, %d failed (graphviz: %t)\n", changed, rendered, failed, haveDot)
	return nil
}

func perPkgDot(c Contract) string {
	var b strings.Builder
	b.WriteString("digraph deps {\n  rankdir=LR;\n  node [shape=box, fontname=\"sans-serif\"];\n")
	b.WriteString(fmt.Sprintf("  %q [style=filled, fillcolor=\"#cfe2ff\"];\n", c.PkgPath))
	deps := append([]string{}, c.Deps...)
	sort.Strings(deps)
	for _, d := range deps {
		b.WriteString(fmt.Sprintf("  %q -> %q;\n", c.PkgPath, d))
	}
	b.WriteString("}\n")
	return b.String()
}

func globalDot(m *Manifest) string {
	own := map[string]bool{}
	for _, c := range m.Contracts {
		own[c.PkgPath] = true
	}
	contracts := append([]Contract{}, m.Contracts...)
	sort.Slice(contracts, func(i, j int) bool { return contracts[i].PkgPath < contracts[j].PkgPath })

	// Collect edges and the set of nodes that participate in at least one edge
	// (as source or target). Isolated packages — no deps and depended on by
	// nothing — are omitted so the global graph shows only what's connected.
	type edge struct{ from, to string }
	var edges []edge
	linked := map[string]bool{}
	for _, c := range contracts {
		deps := append([]string{}, c.Deps...)
		sort.Strings(deps)
		for _, d := range deps {
			edges = append(edges, edge{c.PkgPath, d})
			linked[c.PkgPath] = true
			linked[d] = true
		}
	}

	var b strings.Builder
	b.WriteString("digraph gnocontracts {\n  rankdir=LR;\n  node [shape=box, fontname=\"sans-serif\"];\n")
	// node declarations, only for linked nodes; moul's own packages filled,
	// external deps left plain. Sorted for deterministic output.
	nodes := make([]string, 0, len(linked))
	for n := range linked {
		nodes = append(nodes, n)
	}
	sort.Strings(nodes)
	for _, n := range nodes {
		if own[n] {
			b.WriteString(fmt.Sprintf("  %q [style=filled, fillcolor=\"#cfe2ff\"];\n", n))
		} else {
			b.WriteString(fmt.Sprintf("  %q;\n", n))
		}
	}
	for _, e := range edges {
		b.WriteString(fmt.Sprintf("  %q -> %q;\n", e.from, e.to))
	}
	b.WriteString("}\n")
	return b.String()
}

// writeIfChanged writes content to path (creating dirs) only if it differs from
// the current file; returns whether it changed.
func writeIfChanged(path, content string) (bool, error) {
	if b, err := os.ReadFile(path); err == nil && string(b) == content {
		return false, nil
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return false, err
	}
	return true, os.WriteFile(path, []byte(content), 0o644)
}
