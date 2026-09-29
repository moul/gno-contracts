package main

import (
	"encoding/json"
	"os"
	"strings"
	"testing"
)

// The harness is only worth trusting if its two pieces of arithmetic are:
// baseline subtraction, and the percent change a pull request is judged on.

func TestDeltasSubtractTheNamedBaseline(t *testing.T) {
	s := &Suite{
		Name: "t",
		Workloads: []Workload{
			{Name: "build", Group: "kv", Ops: one},
			{Name: "insert", Group: "kv", Baseline: "build", Ops: perN},
			{Name: "read", Group: "kv", Baseline: "insert", Ops: perN},
		},
	}
	rows := []Row{
		{Structure: "x", Group: "kv", Workload: "build", Mode: "warm", Value: "str", N: 10, Ops: 1, Gas: 100, Bytes: 0},
		{Structure: "x", Group: "kv", Workload: "insert", Mode: "warm", Value: "str", N: 10, Ops: 10, Gas: 600, Bytes: 500},
		{Structure: "x", Group: "kv", Workload: "read", Mode: "warm", Value: "str", N: 10, Ops: 10, Gas: 900, Bytes: 500},
	}
	Deltas(s, rows)
	if rows[1].DGas != 500 || rows[1].DBytes != 500 {
		t.Fatalf("insert delta = %d gas, %d bytes; want 500, 500", rows[1].DGas, rows[1].DBytes)
	}
	// A read costs gas and no storage: the bytes must cancel exactly.
	if rows[2].DGas != 300 || rows[2].DBytes != 0 {
		t.Fatalf("read delta = %d gas, %d bytes; want 300, 0", rows[2].DGas, rows[2].DBytes)
	}
}

// A baseline in a different mode is a different scenario. This caught a real
// bug: cold workloads were subtracting the warm baseline, which made every
// cold figure look negative.
func TestDeltasMatchTheBaselineMode(t *testing.T) {
	s := &Suite{
		Name: "t",
		Workloads: []Workload{
			{Name: "cold_base", Group: "kv", Mode: "cold", Ops: one},
			{Name: "cold_read", Group: "kv", Mode: "cold", Baseline: "cold_base", Ops: perN},
		},
	}
	rows := []Row{
		{Structure: "x", Group: "kv", Workload: "cold_base", Mode: "cold", Value: "str", N: 10, Ops: 1, Gas: 1000},
		{Structure: "x", Group: "kv", Workload: "cold_read", Mode: "cold", Value: "str", N: 10, Ops: 10, Gas: 1700},
		// a warm row with the same name must not be picked up
		{Structure: "x", Group: "kv", Workload: "cold_base", Mode: "warm", Value: "str", N: 10, Ops: 1, Gas: 5},
	}
	Deltas(s, rows)
	if rows[1].DGas != 700 {
		t.Fatalf("cold_read delta = %d; want 700", rows[1].DGas)
	}
}

func TestRowKeySeparatesModes(t *testing.T) {
	a := Row{Structure: "p/nt/avl/v0", Value: "str", Mode: "warm", Workload: "get", N: 100}
	b := a
	b.Mode = "cold"
	if a.Key() == b.Key() {
		t.Fatal("warm and cold rows collide on the same key")
	}
}

func TestPctHandlesZeroBaseline(t *testing.T) {
	for _, tt := range []struct {
		before, after int64
		want          float64
	}{
		{0, 0, 0},
		{0, 5, 100},
		{100, 150, 50},
		{100, 50, -50},
		{-100, -150, -50},
	} {
		if got := pct(tt.before, tt.after); got != tt.want {
			t.Errorf("pct(%d, %d) = %v; want %v", tt.before, tt.after, got, tt.want)
		}
	}
}

func TestEnvIDIsStableAndFilesystemSafe(t *testing.T) {
	e := Env{OS: "darwin", Arch: "arm64", CPU: "Apple M4 Max", CPUs: 16}
	e2 := DetectEnv("")
	if e2.ID == "" {
		t.Fatal("DetectEnv produced no id")
	}
	for _, bad := range []string{"/", " ", ".."} {
		if strings.Contains(e2.ID, bad) {
			t.Fatalf("id %q contains %q", e2.ID, bad)
		}
	}
	_ = e
}

func nameMatchesImports(st Structure) bool {
	if len(st.Imports) == 0 {
		return strings.HasPrefix(st.Name, "builtin")
	}
	for _, imp := range st.Imports {
		p := strings.TrimPrefix(strings.Trim(imp, `"`), "gno.land/")
		if strings.Contains(st.Name, p) {
			return true
		}
	}
	return false
}

func TestTrimVersionStripsOnlyTheVersionElement(t *testing.T) {
	for in, want := range map[string]string{
		"p/moul/ulist/v1":        "p/moul/ulist",
		"p/nt/avl/v0":            "p/nt/avl",
		"p/moul/x/daily/trie/v0": "p/moul/x/daily/trie",
		"p/moul/kit/store":       "p/moul/kit/store",
		"p/moul/v2thing/notaver": "p/moul/v2thing/notaver",
	} {
		if got := trimVersion(in); got != want {
			t.Errorf("trimVersion(%q) = %q; want %q", in, got, want)
		}
	}
}

// Every candidate must render into gno that at least parses as a template, and
// every workload must name a baseline that exists in its own group.
func TestSuitesAreWellFormed(t *testing.T) {
	for name, s := range suites {
		seen := map[string]Workload{}
		for _, w := range s.Workloads {
			seen[w.Group+"/"+w.Name] = w
		}
		for _, w := range s.Workloads {
			if w.Baseline == "" {
				continue
			}
			if _, ok := seen[w.Group+"/"+w.Baseline]; !ok {
				t.Errorf("%s: workload %s/%s names baseline %q, which does not exist",
					name, w.Group, w.Name, w.Baseline)
			}
		}
		for _, st := range s.Structures {
			// The displayed name must name what the candidate actually
			// imports. "avl" reads like a language feature;
			// "p/nt/avl/v0" reads like a package with an author and a
			// version, which is what it is.
			if !nameMatchesImports(st) {
				t.Errorf("%s: candidate %q names none of its imports %v, and does not start with \"builtin\"",
					name, st.Name, st.Imports)
			}
			for wl := range st.Skip {
				if _, ok := seen[st.Group+"/"+wl]; !ok {
					t.Errorf("%s: candidate %q skips %q, which is not a workload in group %s",
						name, st.Name, wl, st.Group)
				}
			}
			if _, err := render(s.Template, scenarioData{
				Imports: st.Imports, Decl: st.Decl, Ops: st.Ops,
				ValueExpr: valueExprs["str"], BuildBody: buildBodyFor(st.Group),
				Body: "", N: 8,
			}); err != nil {
				t.Errorf("%s: candidate %q does not render: %v", name, st.Name, err)
			}
		}
	}
}

// The dashboard is one file with the whole dataset inlined. The failure mode
// that matters is a payload that does not parse, which turns the page blank
// with no error anywhere. Generate one and read it back.
func TestHTMLPayloadRoundTrips(t *testing.T) {
	s := suites["storage"]
	f := &File{
		Schema: schemaVersion, Suite: "storage", UpdatedAt: nowUTC(),
		Env:  Env{ID: "test-env", OS: "linux", Arch: "amd64", CPU: "Test CPU", CPUs: 4, GoVer: "go1.25.9", GnoCommit: "deadbeefcafe"},
		Rows: map[string]Row{},
	}
	r := Row{
		Structure: "p/nt/avl/v0", Group: "kv", Workload: "tx_read", Mode: "cold",
		Value: "str", N: 1000, Ops: 1, Gas: 10, Bytes: 0, DGas: 7, Stable: true,
		MeasuredAt: nowUTC(), GnoCommit: "deadbeefcafe",
	}
	f.Rows[r.Key()] = r

	dir := t.TempDir()
	out := dir + "/storage.html"
	if err := writeHTML(s, []*File{f}, out); err != nil {
		t.Fatal(err)
	}
	b, err := os.ReadFile(out)
	if err != nil {
		t.Fatal(err)
	}
	page := string(b)
	if strings.Contains(page, "/*DATA*/") {
		t.Fatal("the data placeholder was not replaced: the page would render empty")
	}
	start := strings.Index(page, "var DATA = ")
	end := strings.Index(page, ";\nvar S = DATA.suite")
	if start < 0 || end < 0 {
		t.Fatal("could not find the embedded payload")
	}
	var back htmlData
	if err := json.Unmarshal([]byte(page[start+len("var DATA = "):end]), &back); err != nil {
		t.Fatalf("embedded payload does not parse: %v", err)
	}
	if len(back.Files) != 1 || len(back.Files[0].Rows) != 1 {
		t.Fatalf("payload lost rows: %+v", back.Files)
	}
	if back.Files[0].Rows[0].Structure != "p/nt/avl/v0" {
		t.Fatalf("payload mangled the row: %+v", back.Files[0].Rows[0])
	}
	if len(back.Suite.Structures) != len(s.Structures) {
		t.Fatalf("payload has %d candidates, suite has %d", len(back.Suite.Structures), len(s.Structures))
	}
}

// Markdown must degrade to something for a suite that persists nothing, rather
// than printing empty storage tables.
func TestMarkdownHandlesASuiteWithNoStorage(t *testing.T) {
	s := suites["digest"]
	f := &File{Schema: schemaVersion, Suite: "digest", UpdatedAt: nowUTC(),
		Env: Env{ID: "test-env"}, Rows: map[string]Row{}}
	r := Row{Structure: "crypto/sha256", Group: "digest", Workload: "once", Mode: "warm",
		Value: "str", N: 1024, Ops: 1, Gas: 50, DGas: 20, Stable: true, MeasuredAt: nowUTC()}
	f.Rows[r.Key()] = r
	md := Markdown(s, []*File{f})
	if strings.Contains(md, "## Storage per entry") {
		t.Error("digest suite printed a storage section it has no data for")
	}
	if strings.Contains(md, "## One transaction, one operation") {
		t.Error("digest suite printed the transaction section it has no workloads for")
	}
	if !strings.Contains(md, "crypto/sha256") {
		t.Error("digest suite report does not mention its own candidate")
	}
}
