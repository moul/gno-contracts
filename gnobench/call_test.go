package main

import (
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/gnolang/gno/tm2/pkg/std"
	"github.com/gnolang/gno/tm2/pkg/store/types"
)

const counterSrc = `package counter

var count int

func Inc(cur realm, by int) int {
	count += by
	return count
}
`

// writeRealm lays out a realm in a temporary directory, the way a realm
// outside this repository reaches the call command.
func writeRealm(t *testing.T, path string, files map[string]string) string {
	t.Helper()
	dir := t.TempDir()
	files["gnomod.toml"] = "module = \"" + path + "\"\ngno = \"0.9\"\n"
	for name, body := range files {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return dir
}

func needGnoroot(t *testing.T) string {
	t.Helper()
	root := os.Getenv("GNOROOT")
	if root == "" {
		t.Skip("GNOROOT is not set: a measurement needs the stdlibs")
	}
	return root
}

// The setup has to be committed, not just run: the measured call reads what
// it left behind. If setup and measurement shared a transaction the result
// would still be right, so the cold read is asserted too.
func TestCallMeasuresOneCommittedColdCall(t *testing.T) {
	gnoroot := needGnoroot(t)
	dir := writeRealm(t, "gno.land/r/scratch/counter", map[string]string{"counter.gno": counterSrc})
	mpkg, err := readRealm(dir)
	if err != nil {
		t.Fatal(err)
	}
	c := callSpec{Call: "Inc(cross, 10)", Setup: "Inc(cross, {i})", Caller: defaultCaller, SetupBy: defaultCaller}
	for _, tc := range []struct {
		n    int
		want string
	}{
		{0, "10"},
		{4, "16"}, // the setup adds 0+1+2+3
	} {
		r, err := measureCall(gnoroot, nil, mpkg, c, tc.n)
		if err != nil {
			t.Fatalf("n=%d: %v", tc.n, err)
		}
		if r.Result != tc.want {
			t.Fatalf("n=%d: the call returned %q, want %q", tc.n, r.Result, tc.want)
		}
		if r.VMGas <= 0 || r.StoreGas <= 0 || r.Total != r.VMGas+r.StoreGas {
			t.Fatalf("n=%d: vm %d + store %d should be a positive total %d", tc.n, r.VMGas, r.StoreGas, r.Total)
		}
		// Cold: the realm's state comes off the store, and goes back to it.
		if r.Base.Gets == 0 || r.Base.Sets == 0 {
			t.Fatalf("n=%d: base store saw %d reads and %d writes; a cold call needs both", tc.n, r.Base.Gets, r.Base.Sets)
		}
	}
}

// -register has to leave the caller registered by the time the measured call
// runs, which is the point of having it.
func TestCallRegistersTheCaller(t *testing.T) {
	gnoroot := needGnoroot(t)
	dir := writeRealm(t, "gno.land/r/scratch/whoami", map[string]string{"whoami.gno": `package whoami

import "gno.land/r/sys/users"

func Name(cur realm) string {
	u := users.ResolveAddress(cur.Previous().Address())
	if u == nil {
		return "nobody"
	}
	return u.Name()
}
`})
	mpkg, err := readRealm(dir)
	if err != nil {
		t.Fatal(err)
	}
	imports, err := realmImports(dir)
	if err != nil {
		t.Fatal(err)
	}
	abs, err := filepath.Abs(".")
	if err != nil {
		t.Fatal(err)
	}
	pkgs, err := loadCallDeps(gnoroot, imports, []string{filepath.Dir(abs), filepath.Join(gnoroot, "examples")})
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct{ register, want string }{
		{"", "nobody"},
		{"alice", "alice"},
	} {
		c := callSpec{Call: "Name(cross)", Caller: defaultCaller, SetupBy: defaultCaller, Register: tc.register}
		r, err := measureCall(gnoroot, pkgs, mpkg, c, 0)
		if err != nil {
			t.Fatalf("register %q: %v", tc.register, err)
		}
		if !strings.Contains(r.Result, tc.want) {
			t.Fatalf("register %q: the call returned %s, want %s", tc.register, r.Result, tc.want)
		}
	}
}

// captureStdout runs fn with os.Stdout redirected, and returns what it printed.
func captureStdout(t *testing.T, fn func() error) string {
	t.Helper()
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	old := os.Stdout
	os.Stdout = w
	done := make(chan []byte)
	go func() {
		b, _ := io.ReadAll(r)
		done <- b
	}()
	ferr := fn()
	os.Stdout = old
	w.Close()
	out := <-done
	if ferr != nil {
		t.Fatal(ferr)
	}
	return string(out)
}

// Given -dir twice, call measures both versions on the same plan and reports
// after minus before. The second version also appends to a slice, so it has
// to cost more and store more while returning the same thing.
func TestCallComparesTwoVersions(t *testing.T) {
	gnoroot := needGnoroot(t)
	const path = "gno.land/r/scratch/counter"
	before := writeRealm(t, path, map[string]string{"counter.gno": counterSrc})
	after := writeRealm(t, path, map[string]string{"counter.gno": `package counter

var (
	count   int
	history []int
)

func Inc(cur realm, by int) int {
	count += by
	history = append(history, by)
	return count
}
`})
	out := captureStdout(t, func() error {
		return cmdCall([]string{"-dir", before, "-dir", after, "-gnoroot", gnoroot,
			"-call", "Inc(cross, 10)", "-setup", "Inc(cross, {i})", "-n", "0,2", "-repeat", "1", "-json"})
	})
	var pairs []callPair
	if err := json.Unmarshal([]byte(out), &pairs); err != nil {
		t.Fatalf("%v, in:\n%s", err, out)
	}
	if len(pairs) != 2 {
		t.Fatalf("got %d pairs, want one per setup count:\n%s", len(pairs), out)
	}
	for i, want := range []string{"10", "11"} { // the setup adds 0+1
		p := pairs[i]
		if p.Before.Err != "" || p.After.Err != "" {
			t.Fatalf("setup=%d: before %q, after %q", p.Setup, p.Before.Err, p.After.Err)
		}
		if p.Before.Result != want || p.After.Result != want {
			t.Fatalf("setup=%d: returned %q and %q, want %q from both", p.Setup, p.Before.Result, p.After.Result, want)
		}
		d := p.Diff
		if d == nil {
			t.Fatalf("setup=%d: no diff although both sides succeeded", p.Setup)
		}
		if d.Total != p.After.Total-p.Before.Total || d.Bytes != p.After.Bytes-p.Before.Bytes {
			t.Fatalf("setup=%d: diff %+v is not after minus before", p.Setup, *d)
		}
		if d.VMGas <= 0 || d.Bytes <= 0 {
			t.Fatalf("setup=%d: the version that also appends should cost and store more: vm %+d, bytes %+d", p.Setup, d.VMGas, d.Bytes)
		}
		if !d.SameResult {
			t.Fatalf("setup=%d: same return value reported as different", p.Setup)
		}
	}
}

func TestDirListTakesAtMostTwo(t *testing.T) {
	var d dirList
	for _, v := range []string{"before", "after"} {
		if err := d.Set(v); err != nil {
			t.Fatal(err)
		}
	}
	if err := d.Set("third"); err == nil {
		t.Fatal("a third -dir was accepted")
	}
	if !reflect.DeepEqual([]string(d), []string{"before", "after"}) {
		t.Fatalf("dirList = %v", d)
	}
}

func TestDiffCalls(t *testing.T) {
	before := callResult{VMGas: 100, StoreGas: 900, Total: 1000, Bytes: 50, Deposit: 5000, Base: kvCounts{Gets: 3, Sets: 2}, Result: "1"}
	after := callResult{VMGas: 120, StoreGas: 859, Total: 979, Bytes: 40, Deposit: 4000, Base: kvCounts{Gets: 2, Sets: 2}, Result: "1"}
	want := &callDiff{VMGas: 20, StoreGas: -41, Total: -21, Bytes: -10, Deposit: -1000, Base: kvCounts{Gets: -1}, SameResult: true}
	if got := diffCalls(before, after); !reflect.DeepEqual(got, want) {
		t.Fatalf("diffCalls = %+v, want %+v", got, want)
	}
	after.Result = "2"
	if diffCalls(before, after).SameResult {
		t.Fatal("different return values reported as the same")
	}
	// Half a comparison is not one.
	after.Err = "boom"
	if d := diffCalls(before, after); d != nil {
		t.Fatalf("diffCalls with a failed side = %+v, want nil", d)
	}
}

func TestCompareMarkdown(t *testing.T) {
	before := callResult{Setup: 1, VMGas: 100, StoreGas: 900, Total: 1000, Bytes: 50, Deposit: 5000, Denom: "ugnot", Result: "1", Stable: true}
	after := before
	after.VMGas, after.StoreGas, after.Total, after.Bytes, after.Deposit, after.Result = 120, 859, 979, 40, 4000, "2"
	pairs := []callPair{{Setup: 1, Before: before, After: after, Diff: diffCalls(before, after)}}
	realms := []*std.MemPackage{{Path: "gno.land/r/x/a"}, {Path: "gno.land/r/x/b"}}
	md := compareMarkdown([]string{"old", "new"}, realms, callSpec{Call: "F(cross)", Caller: defaultCaller}, "workspace", Env{}, pairs)
	for _, want := range []string{
		"| 1 | before | 100 | 900 | **1,000** |",
		"| | after | 120 | 859 | **979** |",
		"| | **Δ** | +20 | -41 | **-21** (-2.1%) | 0 | 0 | -10 | -1,000 ugnot | 0s | **differs** |",
		"**differs**: the two versions returned different values",
		"- after: `new`, deployed at `gno.land/r/x/b`",
		"deploy at different paths",
	} {
		if !strings.Contains(md, want) {
			t.Errorf("compareMarkdown lacks %q, in:\n%s", want, md)
		}
	}
}

func TestPseudoVersionRev(t *testing.T) {
	for v, want := range map[string]string{
		"v0.0.0-20261124102148-a0f7756e4e29":                    "a0f7756e4e29",
		"v1.2.4-0.20261124102148-a0f7756e4e29":                  "a0f7756e4e29",
		"v1.2.3-pre.0.20261124102148-a0f7756e4e29+incompatible": "a0f7756e4e29",
		"v0.1.0":  "", // a release names no commit
		"(devel)": "",
		"":        "",
	} {
		if got := pseudoVersionRev(v); got != want {
			t.Errorf("pseudoVersionRev(%q) = %q, want %q", v, got, want)
		}
	}
}

func TestVMMismatch(t *testing.T) {
	const full = "a0f7756e4e29c0ffee00000000000000000000aa"
	for _, tc := range []struct {
		linked, gnoroot string
		warn            bool
	}{
		{"a0f7756e4e29", full, false}, // a pseudo-version's 12 digits
		{full, full, false},           // what install-local records
		{"660decca0760", full, true},
		{"", full, false},           // a tagged release: cannot tell
		{"a0f7756e4e29", "", false}, // GNOROOT is not a git checkout
	} {
		w := vmMismatch(tc.linked, tc.gnoroot)
		if (w != "") != tc.warn {
			t.Errorf("vmMismatch(%q, %q) = %q, want a warning: %v", tc.linked, tc.gnoroot, w, tc.warn)
		}
		if tc.warn && (!strings.Contains(w, shortCommit(tc.linked)) || !strings.Contains(w, shortCommit(tc.gnoroot))) {
			t.Errorf("the warning should name both commits: %s", w)
		}
	}
}

// The table carries the warning too, because the table is what gets pasted
// somewhere and stderr is not.
func TestCallMarkdownWarnsOfAMismatch(t *testing.T) {
	linked := linkedGnoCommit()
	if linked == "" {
		t.Skip("this test binary does not know its gno commit")
	}
	rows := []callResult{{Setup: 0, Total: 1, Stable: true}}
	c := callSpec{Call: "F(cross)", Caller: defaultCaller}
	same := callMarkdown("gno.land/r/x/a", c, "workspace", Env{GnoCommit: linked}, rows)
	other := callMarkdown("gno.land/r/x/a", c, "workspace", Env{GnoCommit: strings.Repeat("f", 40)}, rows)
	if strings.Contains(same, "⚠️") {
		t.Errorf("warned although GNOROOT is the linked commit:\n%s", same)
	}
	if !strings.Contains(other, "⚠️ the VM linked into gnobench is gno") {
		t.Errorf("no warning although GNOROOT is another commit:\n%s", other)
	}
}

func TestCheckCallExpr(t *testing.T) {
	for _, tc := range []struct {
		expr string
		ok   bool
	}{
		{`PostMessage(cross, "hello")`, true},
		{`Noop(cur)`, true},
		{`PostMessage`, false},                        // not a call
		{`social.PostMessage(cross, "hello")`, false}, // the package is implied
		{`PostMessage()`, false},                      // no realm argument
		{`PostMessage(cross, "unterminated)`, false},
	} {
		err := checkCallExpr("-call", tc.expr)
		if (err == nil) != tc.ok {
			t.Fatalf("checkCallExpr(%q) = %v, want ok=%v", tc.expr, err, tc.ok)
		}
	}
}

// Only the realm's production imports outside the stdlibs are worth loading.
func TestRealmImportsSkipsStdlibsAndTests(t *testing.T) {
	dir := writeRealm(t, "gno.land/r/scratch/imports", map[string]string{
		"a.gno":      "package imports\n\nimport (\n\t\"strings\"\n\n\t\"gno.land/p/nt/ufmt/v0\"\n)\n",
		"b.gno":      "package imports\n\nimport (\n\t\"chain/runtime\"\n\n\t\"gno.land/p/nt/bptree/v0\"\n\t\"gno.land/p/nt/ufmt/v0\"\n)\n",
		"a_test.gno": "package imports\n\nimport \"gno.land/p/nt/uassert/v0\"\n",
	})
	got, err := realmImports(dir)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"gno.land/p/nt/bptree/v0", "gno.land/p/nt/ufmt/v0"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("realmImports = %v, want %v", got, want)
	}
}

// The flat formula is the one gno.land's base store charges, and most of a
// call's I/O lands there. Pricing it like the depth-priced main store made a
// PostMessage cost twice what a node charged for it.
func TestFlatStoreGas(t *testing.T) {
	cfg := types.GasConfig{ReadCostFlat: 10, ReadCostPerByte: 2, WriteCostFlat: 100, WriteCostPerByte: 3, DeleteCost: 50}
	// 2 reads of 5 bytes in all, 1 write of 4 bytes, 1 delete.
	if got, want := flatStoreGas(cfg, 2, 5, 1, 4, 1), int64(2*10+5*2+100+4*3+50); got != want {
		t.Fatalf("flatStoreGas = %d, want %d", got, want)
	}
}

func TestLocalOnlyRefusesToDownload(t *testing.T) {
	_, err := localOnly{}.FetchPackage("gno.land/p/someone/missing/v0")
	if err == nil || !strings.Contains(err.Error(), "gno.land/p/someone/missing/v0") {
		t.Fatalf("FetchPackage = %v, want an error naming the package", err)
	}
}
