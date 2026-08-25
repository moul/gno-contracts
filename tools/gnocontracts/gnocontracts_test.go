package main

import (
	"os"
	"path/filepath"
	"reflect"
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
	writeFile(t, dir, "pkg.gno", "package p\nimport \"gno.land/p/moul/md/v1\"\n")
	writeFile(t, dir, "pkg_test.gno", "package p\nimport \"gno.land/p/nt/uassert/v0\"\n")
	writeFile(t, dir, "z1_filetest.gno", "package main\nimport \"gno.land/p/moul/self/v1\"\n")

	// Runtime deps: only the non-test import.
	deps, err := parseDeps(dir)
	if err != nil {
		t.Fatal(err)
	}
	if want := []string{"gno.land/p/moul/md/v1"}; !reflect.DeepEqual(deps, want) {
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
	writeFile(t, dir, "x.gno", "package x\nimport \"gno.land/p/moul/md/v1\"\n")
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
	if want := []string{"gno.land/p/moul/md/v1"}; !reflect.DeepEqual(c.Deps, want) {
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
	body := "package p\n\nimport (\n\t\"strings\"\n\t\"gno.land/p/moul/md/v1\"\n\talias \"gno.land/p/nt/avl/v0\"\n)\n\nimport \"gno.land/r/moul/hello/v1\"\n"
	writeFile(t, dir, "p.gno", body)
	imps, err := parseImports(filepath.Join(dir, "p.gno"))
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]bool{"strings": true, "gno.land/p/moul/md/v1": true, "gno.land/p/nt/avl/v0": true, "gno.land/r/moul/hello/v1": true}
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
			body: "/*\nPackage svg …\n\nExample:\n\n\timport \"gno.land/p/moul/svg\"\n*/\npackage svg // import \"gno.land/p/moul/svg\"\n\nimport \"gno.land/p/moul/md/v1\"\n",
			want: []string{"gno.land/p/moul/md/v1"},
		},
		{
			name: "line-commented import",
			body: "package p\n\n// import \"gno.land/p/moul/ghost/v1\"\nimport \"strings\"\n",
			want: []string{"strings"},
		},
		{
			name: "commented entry inside an import group",
			body: "package p\n\nimport (\n\t\"strings\"\n\t// \"gno.land/p/moul/ghost/v1\"\n\t\"gno.land/p/moul/md/v1\"\n)\n",
			want: []string{"strings", "gno.land/p/moul/md/v1"},
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
