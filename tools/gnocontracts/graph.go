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
//	_assets/gno.land/r/moul/hello/v0/deps.{dot,svg,png}
//	_assets/graph.{dot,svg,png}            (whole-repo graph, EVERY version)
//	_assets/graph-latest.{dot,svg,png}     (one node per package, latest vN)
const assetsDir = "_assets"

// graphLatestBase is the latest-version-only graph embedded in the README. The
// full graph keeps its historical name so existing links stay valid.
const graphLatestBase = "graph-latest"

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

	// global graph — every version of every package
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

	// latest-version-only graph — one node per package, for the README
	lrel := filepath.Join(assetsDir, graphLatestBase+".dot")
	lch, err := writeIfChanged(filepath.Join(root, lrel), latestDot(m))
	if err != nil {
		return err
	}
	if lch {
		changed++
	}
	if err := render(lrel, lch); err != nil {
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

// splitVersion splits a pkgpath into its base and numeric version. The version
// is ALWAYS the last path element (`p/moul/ulist/lplist/v0`, never
// `p/moul/ulist/v0/lplist`), so only the final segment is considered.
func splitVersion(pkgpath string) (base string, n int, ok bool) {
	i := strings.LastIndexByte(pkgpath, '/')
	if i < 0 {
		return pkgpath, 0, false
	}
	seg := pkgpath[i+1:]
	if len(seg) < 2 || seg[0] != 'v' {
		return pkgpath, 0, false
	}
	num := 0
	for _, c := range seg[1:] {
		if c < '0' || c > '9' {
			return pkgpath, 0, false
		}
		num = num*10 + int(c-'0')
	}
	return pkgpath[:i], num, true
}

// latestOwn maps each of OUR package bases to its highest version's pkgpath.
// Comparison is numeric, so v10 beats v9 — a string sort would not.
//
// Only our own packages are collapsed. An external dependency's version set is
// whatever happens to be referenced here, not the full picture, so folding
// `p/nt/avl/v0` and `p/nt/avl/v1` together would assert something we cannot
// know; external nodes keep their exact version.
func latestOwn(m *Manifest) map[string]string {
	best := map[string]int{}
	out := map[string]string{}
	for _, c := range m.Contracts {
		base, n, ok := splitVersion(c.PkgPath)
		if !ok {
			continue
		}
		if cur, seen := best[base]; !seen || n > cur {
			best[base] = n
			out[base] = c.PkgPath
		}
	}
	return out
}

// latestDot renders a PACKAGE-level graph: one node per package, pinned to its
// latest version, with every edge re-pointed onto the surviving nodes.
//
// Re-pointing rather than dropping is deliberate. If `r/foo/v0` depends on
// `p/bar/v0` and `p/bar` has since gained a `v1`, simply deleting the `v0` node
// would leave `r/foo` looking dependency-less, which is a worse lie than
// showing the edge against the package. The contract of this graph is "package
// A depends on package B"; the full graph keeps the per-version truth.
//
// Self-edges that collapse onto one node (a `v1` importing its own `v0`) are
// dropped — they would render as meaningless loops.
func latestDot(m *Manifest) string {
	latest := latestOwn(m)
	own := map[string]bool{}
	for _, c := range m.Contracts {
		own[c.PkgPath] = true
	}

	// canon maps any node to the node that survives the collapse.
	canon := func(node string) string {
		if !own[node] {
			return node // external: keep the exact version
		}
		if base, _, ok := splitVersion(node); ok {
			if l, found := latest[base]; found {
				return l
			}
		}
		return node
	}

	type edge struct{ from, to string }
	seen := map[edge]bool{}
	var edges []edge
	linked := map[string]bool{}

	contracts := append([]Contract{}, m.Contracts...)
	sort.Slice(contracts, func(i, j int) bool { return contracts[i].PkgPath < contracts[j].PkgPath })
	for _, c := range contracts {
		from := canon(c.PkgPath)
		deps := append([]string{}, c.Deps...)
		sort.Strings(deps)
		for _, d := range deps {
			to := canon(d)
			if from == to {
				continue // a version importing an older self
			}
			e := edge{from, to}
			if seen[e] {
				continue // two versions contributing the same package-level edge
			}
			seen[e] = true
			edges = append(edges, e)
			linked[from] = true
			linked[to] = true
		}
	}

	var b strings.Builder
	b.WriteString("digraph gnocontracts_latest {\n  rankdir=LR;\n  node [shape=box, fontname=\"sans-serif\"];\n")
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
	sort.Slice(edges, func(i, j int) bool {
		if edges[i].from != edges[j].from {
			return edges[i].from < edges[j].from
		}
		return edges[i].to < edges[j].to
	})
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
