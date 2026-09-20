package main

import (
	"os"
	"path/filepath"
	"reflect"
	"regexp"
	"strings"
	"testing"
)

func writeFile(t *testing.T, dir, name, body string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestParseDepsExcludesTestsAndFiletests(t *testing.T) {
	dir := t.TempDir()
	writeFile(t, dir, "pkg.gno", "package p\nimport \"gno.land/p/moul/md/v0\"\n")
	writeFile(t, dir, "pkg_test.gno", "package p\nimport \"gno.land/p/nt/uassert/v0\"\n")
	writeFile(t, dir, "z1_filetest.gno", "package main\nimport \"gno.land/p/moul/self/v1\"\n")

	// Runtime deps: only the non-test import.
	deps, err := parseDeps(dir)
	if err != nil {
		t.Fatal(err)
	}
	if want := []string{"gno.land/p/moul/md/v0"}; !reflect.DeepEqual(deps, want) {
		t.Fatalf("parseDeps = %v, want %v", deps, want)
	}

	// With tests included (vendoring mode): all three imports appear.
	all, err := parseDepsMode(dir, true)
	if err != nil {
		t.Fatal(err)
	}
	if len(all) != 3 {
		t.Fatalf("parseDepsMode(includeTests) = %v, want 3 entries", all)
	}
}

func TestDropString(t *testing.T) {
	got := dropString([]string{"a", "b", "a", "c"}, "a")
	if want := []string{"b", "c"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("dropString = %v, want %v", got, want)
	}
	if got := dropString(nil, "a"); len(got) != 0 {
		t.Fatalf("dropString(nil) = %v", got)
	}
}

func TestIsVersion(t *testing.T) {
	cases := map[string]bool{"v1": true, "v0": true, "v12": true, "v": false, "1": false, "vx": false, "va1": false, "": false}
	for s, want := range cases {
		if got := isVersion(s); got != want {
			t.Errorf("isVersion(%q) = %v, want %v", s, got, want)
		}
	}
}

func TestDeriveContractStripsSelfDep(t *testing.T) {
	dir := t.TempDir()
	writeFile(t, dir, "x.gno", "package x\nimport \"gno.land/p/moul/md/v0\"\n")
	// A filetest that self-imports must NOT produce a self-dependency.
	writeFile(t, dir, "z_filetest.gno", "package main\nimport \"gno.land/p/moul/x/v1\"\n")

	c, err := deriveContract("gno.land/p/moul/x/v1", "p/moul/x/v1", dir)
	if err != nil {
		t.Fatal(err)
	}
	if c.Kind != "p" || c.Version != "v1" || c.Name != "x" {
		t.Fatalf("derived = %+v", c)
	}
	for _, d := range c.Deps {
		if d == c.PkgPath {
			t.Fatalf("self-dependency leaked into deps: %v", c.Deps)
		}
	}
	if want := []string{"gno.land/p/moul/md/v0"}; !reflect.DeepEqual(c.Deps, want) {
		t.Fatalf("deps = %v, want %v", c.Deps, want)
	}
}

func TestDeriveContractRejectsUnversioned(t *testing.T) {
	dir := t.TempDir()
	writeFile(t, dir, "x.gno", "package x\n")
	if _, err := deriveContract("gno.land/p/moul/x", "p/moul/x", dir); err == nil {
		t.Fatal("expected error for un-versioned module path")
	}
}

func TestTopoOrderDepsFirst(t *testing.T) {
	cs := []Contract{
		{PkgPath: "a", Deps: []string{"b"}},
		{PkgPath: "b", Deps: []string{"c"}},
		{PkgPath: "c"},
		{PkgPath: "d", Deps: []string{"external/not/selected"}},
	}
	ord, err := topoOrder(cs)
	if err != nil {
		t.Fatal(err)
	}
	pos := map[string]int{}
	for i, c := range ord {
		pos[c.PkgPath] = i
	}
	if !(pos["c"] < pos["b"] && pos["b"] < pos["a"]) {
		t.Fatalf("expected c<b<a, got order %v", pos)
	}
	if len(ord) != 4 {
		t.Fatalf("expected all 4 contracts, got %d", len(ord))
	}
}

func TestTopoOrderCycleDetected(t *testing.T) {
	cs := []Contract{
		{PkgPath: "a", Deps: []string{"b"}},
		{PkgPath: "b", Deps: []string{"a"}},
	}
	if _, err := topoOrder(cs); err == nil {
		t.Fatal("expected a cycle error")
	}
}

func TestTopoOrderSelfDepTolerated(t *testing.T) {
	// A self-dependency must not be mistaken for a cycle.
	cs := []Contract{{PkgPath: "a", Deps: []string{"a"}}}
	if _, err := topoOrder(cs); err != nil {
		t.Fatalf("self-dep should be tolerated, got %v", err)
	}
}

func TestParseImports(t *testing.T) {
	dir := t.TempDir()
	body := "package p\n\nimport (\n\t\"strings\"\n\t\"gno.land/p/moul/md/v0\"\n\talias \"gno.land/p/nt/avl/v0\"\n)\n\nimport \"gno.land/r/moul/hello/v0\"\n"
	writeFile(t, dir, "p.gno", body)
	imps, err := parseImports(filepath.Join(dir, "p.gno"))
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]bool{"strings": true, "gno.land/p/moul/md/v0": true, "gno.land/p/nt/avl/v0": true, "gno.land/r/moul/hello/v0": true}
	if len(imps) != len(want) {
		t.Fatalf("imports = %v", imps)
	}
	for _, i := range imps {
		if !want[i] {
			t.Errorf("unexpected import %q", i)
		}
	}
}

// Imports that only *look* like imports — inside a doc comment showing example
// usage, or commented out — must not be reported as dependencies. Regression:
// p/moul/svg/v1/doc.gno documents `import "gno.land/p/moul/svg"`, which the
// line-based scanner used to take literally, inventing a dependency on a
// package present in no checkout and failing `make deps`.
func TestParseImportsIgnoresComments(t *testing.T) {
	cases := []struct {
		name, body string
		want       []string
	}{
		{
			name: "block doc comment with example import",
			body: "/*\nPackage svg …\n\nExample:\n\n\timport \"gno.land/p/moul/svg\"\n*/\npackage svg // import \"gno.land/p/moul/svg\"\n\nimport \"gno.land/p/moul/md/v0\"\n",
			want: []string{"gno.land/p/moul/md/v0"},
		},
		{
			name: "line-commented import",
			body: "package p\n\n// import \"gno.land/p/moul/ghost/v1\"\nimport \"strings\"\n",
			want: []string{"strings"},
		},
		{
			name: "commented entry inside an import group",
			body: "package p\n\nimport (\n\t\"strings\"\n\t// \"gno.land/p/moul/ghost/v1\"\n\t\"gno.land/p/moul/md/v0\"\n)\n",
			want: []string{"strings", "gno.land/p/moul/md/v0"},
		},
		{
			name: "inline block comment on the same line",
			body: "package p\n\nimport \"strings\" /* not \"gno.land/p/moul/ghost/v1\" */\n",
			want: []string{"strings"},
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			dir := t.TempDir()
			writeFile(t, dir, "p.gno", c.body)
			got, err := parseImports(filepath.Join(dir, "p.gno"))
			if err != nil {
				t.Fatal(err)
			}
			if len(got) != len(c.want) {
				t.Fatalf("imports = %v, want %v", got, c.want)
			}
			for i := range got {
				if got[i] != c.want[i] {
					t.Errorf("imports = %v, want %v", got, c.want)
					break
				}
			}
		})
	}
}

func TestClassifyUpstream(t *testing.T) {
	// build a dir with a prod .gno, a test .gno, and a gnomod
	mk := func(prod, test, mod string) string {
		d := t.TempDir()
		writeFile(t, d, "a.gno", prod)
		writeFile(t, d, "a_test.gno", test)
		writeFile(t, d, "gnomod.toml", mod)
		return d
	}
	our := mk("X", "T1", `module = "gno.land/p/moul/x/v2"`)
	cases := []struct {
		name, prod, test, mod, want string
	}{
		{"exact", "X", "T1", `module = "gno.land/p/moul/x/v2"`, "exact"},
		{"gno (meta differs)", "X", "T1", `module = "gno.land/p/moul/x"`, "gno"},
		{"gno-notest (tests differ)", "X", "T2", `module = "gno.land/p/moul/x"`, "gno-notest"},
		{"diff (prod differs)", "Y", "T1", `module = "gno.land/p/moul/x"`, "diff"},
	}
	for _, c := range cases {
		if got := classifyUpstream(our, mk(c.prod, c.test, c.mod)); got != c.want {
			t.Errorf("%s: classifyUpstream = %q, want %q", c.name, got, c.want)
		}
	}
}

// Scratch dot-directories must never be catalogued. The Makefile's toolcheck
// canary lives in p/moul/.toolcheck and an interrupted run can leave it behind;
// if scanContracts picked it up it would land in contracts.json and the README
// table as a phantom package.
func TestScanContractsSkipsDotDirs(t *testing.T) {
	root := t.TempDir()
	mkpkg := func(dir, module string) {
		if err := os.MkdirAll(filepath.Join(root, dir), 0o755); err != nil {
			t.Fatal(err)
		}
		writeFile(t, filepath.Join(root, dir), "gnomod.toml", "module = \""+module+"\"\ngno = \"0.9\"\n")
		writeFile(t, filepath.Join(root, dir), "x.gno", "package x\n")
	}
	mkpkg("p/moul/real/v1", "gno.land/p/moul/real/v1")
	mkpkg("p/moul/.toolcheck", "gno.land/p/moul/toolcheck/v1")
	mkpkg("r/moul/.scratch/v1", "gno.land/r/moul/scratch/v1")

	got, err := scanContracts(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 1 {
		var paths []string
		for _, c := range got {
			paths = append(paths, c.PkgPath)
		}
		t.Fatalf("scanContracts returned %v, want only the real package", paths)
	}
	if got[0].PkgPath != "gno.land/p/moul/real/v1" {
		t.Fatalf("scanContracts = %q", got[0].PkgPath)
	}
}

// A canonical import comment (`package x // import "…"`) tells callers the one
// path this package may be imported as. It must match the module path in the
// package's gnomod.toml — in particular it must carry the /vN segment, since
// rule 1 of this repo is that no contract is ever un-versioned. p/moul/svg/v1
// shipped `// import "gno.land/p/moul/svg"`, pointing at a path that exists
// nowhere, so anyone following the doc would have written an unresolvable
// import. This walks the real trees rather than a fixture: the invariant is
// about the repository, not about a function.
func TestCanonicalImportCommentsMatchModulePath(t *testing.T) {
	root, err := repoRoot()
	if err != nil {
		t.Skipf("not inside the repo: %v", err)
	}
	re := regexp.MustCompile(`(?m)^package\s+\w+\s*//\s*import\s+"([^"]+)"`)

	contracts, err := scanContracts(root)
	if err != nil {
		t.Fatal(err)
	}
	checked := 0
	for _, c := range contracts {
		// srcDir, not Dir: a superseded version has no directory any more,
		// and its files are read out of gnopm's materialized copy. The
		// invariant applies to it just the same.
		dir := filepath.Join(root, filepath.FromSlash(c.srcDir()))
		entries, err := os.ReadDir(dir)
		if err != nil {
			t.Fatal(err)
		}
		for _, e := range entries {
			if e.IsDir() || !strings.HasSuffix(e.Name(), ".gno") {
				continue
			}
			b, err := os.ReadFile(filepath.Join(dir, e.Name()))
			if err != nil {
				t.Fatal(err)
			}
			m := re.FindSubmatch(b)
			if m == nil {
				continue
			}
			checked++
			if got := string(m[1]); got != c.PkgPath {
				t.Errorf("%s/%s: canonical import %q, want %q",
					c.Dir, e.Name(), got, c.PkgPath)
			}
		}
	}
	t.Logf("checked %d canonical import comment(s)", checked)
}

// defaultNetworks is the single place a chain is added or retired, so guard its
// shape: names unique, chain_id and RPC present, and the two live testnets
// actually listed (a silent drop would quietly stop status/publish tracking).
func TestDefaultNetworksAreWellFormed(t *testing.T) {
	nets := defaultNetworks()
	seen := map[string]bool{}
	for _, n := range nets {
		if n.Name == "" || n.ChainID == "" || n.RPC == "" {
			t.Errorf("incomplete network entry: %+v", n)
		}
		if seen[n.Name] {
			t.Errorf("duplicate network %q", n.Name)
		}
		seen[n.Name] = true
	}
	for _, want := range []string{"sapphire", "pearl"} {
		if !seen[want] {
			t.Errorf("live testnet %q missing from defaultNetworks", want)
		}
	}
	if seen["topaz"] {
		t.Error("topaz is retired and must not be a tracked network")
	}
}

// manifest reconciles the catalog's network list from defaultNetworks(), which
// is the ONLY way a network change can land (contracts.json is generated on
// main and the no-generated-files guard rejects PRs that touch it). Retiring a
// network must not drop the historical per-contract `published` entries.
func TestManifestReconcilesNetworksAndKeepsPublished(t *testing.T) {
	root := t.TempDir()
	writeFile(t, root, "gnowork.toml", "")
	if err := os.MkdirAll(filepath.Join(root, "p/moul/real/v1"), 0o755); err != nil {
		t.Fatal(err)
	}
	writeFile(t, filepath.Join(root, "p/moul/real/v1"), "gnomod.toml",
		"module = \"gno.land/p/moul/real/v1\"\ngno = \"0.9\"\n")
	writeFile(t, filepath.Join(root, "p/moul/real/v1"), "x.gno", "package real\n")

	// A catalog carrying a retired network, both in the list and in published.
	writeFile(t, root, "contracts.json", `{
  "networks": [{"name":"topaz","chain_id":"topaz-1","rpc":"https://rpc.topaz.example:443"}],
  "contracts": [{"pkgpath":"gno.land/p/moul/real/v1","dir":"p/moul/real/v1","kind":"p","name":"real","version":"v1","deps":[],"draft":false,
    "published":{"topaz":{"uploaded":true,"tx":"deadbeef"}}}]
}`)

	if err := cmdManifest(root); err != nil {
		t.Fatal(err)
	}
	m, err := loadManifest(root)
	if err != nil {
		t.Fatal(err)
	}

	// Compare against defaultNetworks() itself rather than a hardcoded list:
	// the assertion is "manifest reconciles to the code-owned set", and
	// restating the names here only means editing this test every time a
	// chain is added or retired (it was still asserting betanet the day
	// mainnet replaced it).
	var names, want []string
	for _, n := range m.Networks {
		names = append(names, n.Name)
	}
	for _, n := range defaultNetworks() {
		want = append(want, n.Name)
	}
	if strings.Join(names, ",") != strings.Join(want, ",") {
		t.Fatalf("networks = %v, want the defaultNetworks() set %v", names, want)
	}
	if len(m.Contracts) != 1 {
		t.Fatalf("contracts = %d, want 1", len(m.Contracts))
	}
	pub := m.Contracts[0].Published
	if got, ok := pub["topaz"]; !ok || got.Tx != "deadbeef" {
		t.Errorf("retiring a network dropped its historical published entry: %+v", pub)
	}
	for _, n := range []string{"sapphire", "pearl"} {
		if _, ok := pub[n]; !ok {
			t.Errorf("no published slot created for live network %q", n)
		}
	}
}

func TestSplitVersion(t *testing.T) {
	cases := []struct {
		in   string
		base string
		n    int
		ok   bool
	}{
		{"gno.land/p/moul/md/v0", "gno.land/p/moul/md", 0, true},
		{"gno.land/p/moul/md/v12", "gno.land/p/moul/md", 12, true},
		// The version is the LAST element, even for nested packages.
		{"gno.land/p/moul/ulist/lplist/v0", "gno.land/p/moul/ulist/lplist", 0, true},
		// Not versions.
		{"gno.land/p/moul/md", "gno.land/p/moul/md", 0, false},
		{"gno.land/p/moul/vault", "gno.land/p/moul/vault", 0, false},
		{"gno.land/p/moul/v", "gno.land/p/moul/v", 0, false},
		{"gno.land/p/moul/v1x", "gno.land/p/moul/v1x", 0, false},
		{"nopath", "nopath", 0, false},
	}
	for _, c := range cases {
		base, n, ok := splitVersion(c.in)
		if base != c.base || n != c.n || ok != c.ok {
			t.Errorf("splitVersion(%q) = (%q,%d,%v), want (%q,%d,%v)",
				c.in, base, n, ok, c.base, c.n, c.ok)
		}
	}
}

// TestLatestOwnIsNumeric guards the v10 > v9 case a string sort gets wrong.
func TestLatestOwnIsNumeric(t *testing.T) {
	m := &Manifest{Contracts: []Contract{
		{PkgPath: "gno.land/p/moul/a/v9"},
		{PkgPath: "gno.land/p/moul/a/v10"},
		{PkgPath: "gno.land/p/moul/a/v2"},
	}}
	got := latestOwn(m)["gno.land/p/moul/a"]
	if got != "gno.land/p/moul/a/v10" {
		t.Fatalf("latest = %q, want v10 (numeric compare, not lexical)", got)
	}
}

// TestLatestDotRepointsEdges is the core behaviour: an edge into a superseded
// version must survive, re-pointed at the latest, or the package would render
// as dependency-less.
func TestLatestDotRepointsEdges(t *testing.T) {
	m := &Manifest{Contracts: []Contract{
		{PkgPath: "gno.land/p/moul/lib/v0"},
		{PkgPath: "gno.land/p/moul/lib/v1"},
		{PkgPath: "gno.land/r/moul/app/v0", Deps: []string{"gno.land/p/moul/lib/v0"}},
	}}
	dot := latestDot(m)

	if !strings.Contains(dot, `"gno.land/r/moul/app/v0" -> "gno.land/p/moul/lib/v1"`) {
		t.Errorf("edge should be re-pointed to lib/v1, got:\n%s", dot)
	}
	if strings.Contains(dot, `"gno.land/p/moul/lib/v0"`) {
		t.Errorf("superseded lib/v0 should not appear, got:\n%s", dot)
	}
}

// TestLatestDotDropsSelfEdges: a v1 importing its own v0 collapses to a loop,
// which is noise.
func TestLatestDotDropsSelfEdges(t *testing.T) {
	m := &Manifest{Contracts: []Contract{
		{PkgPath: "gno.land/p/moul/lib/v0"},
		{PkgPath: "gno.land/p/moul/lib/v1", Deps: []string{"gno.land/p/moul/lib/v0"}},
	}}
	dot := latestDot(m)
	if strings.Contains(dot, "->") {
		t.Errorf("a version importing its own predecessor must not render an edge, got:\n%s", dot)
	}
}

// TestLatestDotDedupesEdges: two versions of the same package depending on the
// same lib collapse to ONE package-level edge.
func TestLatestDotDedupesEdges(t *testing.T) {
	m := &Manifest{Contracts: []Contract{
		{PkgPath: "gno.land/p/moul/lib/v0"},
		{PkgPath: "gno.land/r/moul/app/v0", Deps: []string{"gno.land/p/moul/lib/v0"}},
		{PkgPath: "gno.land/r/moul/app/v1", Deps: []string{"gno.land/p/moul/lib/v0"}},
	}}
	dot := latestDot(m)
	if n := strings.Count(dot, "->"); n != 1 {
		t.Errorf("want exactly 1 collapsed edge, got %d:\n%s", n, dot)
	}
}

// TestLatestDotKeepsExternalVersions: we do not know an external package's full
// version set, so folding its versions together would assert something false.
func TestLatestDotKeepsExternalVersions(t *testing.T) {
	m := &Manifest{Contracts: []Contract{
		{PkgPath: "gno.land/r/moul/a/v0", Deps: []string{"gno.land/p/nt/avl/v0"}},
		{PkgPath: "gno.land/r/moul/b/v0", Deps: []string{"gno.land/p/nt/avl/v1"}},
	}}
	dot := latestDot(m)
	for _, want := range []string{"gno.land/p/nt/avl/v0", "gno.land/p/nt/avl/v1"} {
		if !strings.Contains(dot, want) {
			t.Errorf("external %s should be kept verbatim, got:\n%s", want, dot)
		}
	}
}

func TestLatestDotIsDeterministic(t *testing.T) {
	m := &Manifest{Contracts: []Contract{
		{PkgPath: "gno.land/r/moul/z/v0", Deps: []string{"gno.land/p/moul/b/v0", "gno.land/p/moul/a/v0"}},
		{PkgPath: "gno.land/p/moul/a/v0"},
		{PkgPath: "gno.land/p/moul/b/v0"},
	}}
	if latestDot(m) != latestDot(m) {
		t.Fatal("latestDot must be deterministic")
	}
}

// TestRenderGraphSectionIsIdempotent: regen runs on every merge, so a second
// pass must not duplicate or drift the section.
func TestRenderGraphSectionIsIdempotent(t *testing.T) {
	in := "# Title\n\nintro\n\n## Dependency graph\n\nold body\n\n## Contributing\n\ntail\n"
	once := renderGraphSection(in)
	twice := renderGraphSection(once)
	if once != twice {
		t.Errorf("not idempotent:\n--- once ---\n%s\n--- twice ---\n%s", once, twice)
	}
	if !strings.Contains(once, "graph-latest.svg") {
		t.Error("should embed the latest-only graph")
	}
	if !strings.Contains(once, "_assets/graph.svg") {
		t.Error("should link the full graph")
	}
	if strings.Contains(once, "old body") {
		t.Error("old body should be replaced")
	}
	if !strings.Contains(once, "## Contributing\n\ntail\n") {
		t.Error("the following section must be preserved intact")
	}
}

func TestRenderGraphSectionNoSection(t *testing.T) {
	in := "# Title\n\nno graph section here\n"
	if got := renderGraphSection(in); got != in {
		t.Errorf("content without the heading must pass through unchanged, got:\n%s", got)
	}
}

// TestRenderGraphSectionAtEOF covers the section being the last one.
func TestRenderGraphSectionAtEOF(t *testing.T) {
	in := "# Title\n\n## Dependency graph\n\nold\n"
	got := renderGraphSection(in)
	if !strings.Contains(got, "graph-latest.svg") {
		t.Errorf("should still rewrite when the section ends the file, got:\n%s", got)
	}
	if got != renderGraphSection(got) {
		t.Error("must be idempotent at EOF too")
	}
}
