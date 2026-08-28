package main

import (
	"strings"
	"testing"
)

func TestMatchesAny(t *testing.T) {
	cases := []struct {
		dir  string
		sels []string
		want bool
	}{
		{"p/moul/hello/v1", []string{"./..."}, true},
		{"p/moul/hello/v1", []string{"./p/moul/hello"}, true},    // all versions
		{"p/moul/hello/v2", []string{"./p/moul/hello"}, true},    // all versions
		{"p/moul/hello/v1", []string{"./p/moul/hello/v1"}, true}, // exact
		{"p/moul/hello/v2", []string{"./p/moul/hello/v1"}, false},
		{"r/moul/x/daily/blog/v1", []string{"./r/moul/..."}, true},
		{"p/moul/hello/v1", []string{"./r/moul/..."}, false},
		{"p/moul/helloworld/v1", []string{"./p/moul/hello"}, false}, // prefix boundary
	}
	for _, c := range cases {
		if got := matchesAny(c.dir, c.sels); got != c.want {
			t.Errorf("matchesAny(%q, %v) = %v, want %v", c.dir, c.sels, got, c.want)
		}
	}
}

func TestSelectContracts(t *testing.T) {
	cs := []contract{
		{PkgPath: "a", Dir: "p/moul/a/v1"},
		{PkgPath: "b", Dir: "p/moul/b/v1", Ignored: true},
		{PkgPath: "c", Dir: "p/moul/c/v1", Draft: true},
		{PkgPath: "d", Dir: "r/moul/d/v1"}, // not matched by the p/ selector
	}
	sel, skip := selectContracts(cs, []string{"./p/moul/..."})
	if len(sel) != 1 || sel[0].PkgPath != "a" {
		t.Fatalf("selected = %v, want [a]", sel)
	}
	if len(skip) != 2 { // b (ignored) + c (draft); d is simply unmatched
		t.Fatalf("skipped = %v, want 2 (ignored+draft)", skip)
	}
}

func TestTopoOrderDepsFirstWithSelfDep(t *testing.T) {
	cs := []contract{
		{PkgPath: "a", Deps: []string{"b"}},
		{PkgPath: "b"},
		{PkgPath: "c", Deps: []string{"c"}}, // self-dep must be tolerated
	}
	ord, err := topoOrder(cs)
	if err != nil {
		t.Fatalf("topoOrder: %v", err)
	}
	pos := map[string]int{}
	for i, c := range ord {
		pos[c.PkgPath] = i
	}
	if pos["b"] >= pos["a"] {
		t.Fatalf("b must come before a; order %v", pos)
	}
	if len(ord) != 3 {
		t.Fatalf("expected 3 contracts, got %d", len(ord))
	}
}

func TestTxHash(t *testing.T) {
	// raw bytes -> full base64 (never truncated at a non-printable byte).
	got := txHash([]byte{0x00, 0xff, 0x10, 0x20})
	if got != "AP8QIA==" {
		t.Fatalf("txHash = %q, want AP8QIA==", got)
	}
}

func TestWebBaseAndPkgURL(t *testing.T) {
	cases := []struct {
		net          network
		wantBase     string
		pkgpath, url string
	}{
		{
			network{Name: "portal-loop", RPC: "https://rpc.gno.land:443"},
			"https://gno.land",
			"gno.land/p/moul/hello/v1", "https://gno.land/p/moul/hello/v1",
		},
		{
			network{Name: "test6", RPC: "https://rpc.test6.testnets.gno.land:443"},
			"https://test6.testnets.gno.land",
			"gno.land/r/moul/x/daily/blog/v1", "https://test6.testnets.gno.land/r/moul/x/daily/blog/v1",
		},
		{
			network{Name: "gnodev", RPC: "http://127.0.0.1:26657"},
			"http://127.0.0.1:8888",
			"gno.land/p/moul/hello/v1", "http://127.0.0.1:8888/p/moul/hello/v1",
		},
	}
	for _, c := range cases {
		if got := webBase(c.net); got != c.wantBase {
			t.Errorf("webBase(%s) = %q, want %q", c.net.Name, got, c.wantBase)
		}
		if got := pkgURL(c.net, c.pkgpath); got != c.url {
			t.Errorf("pkgURL(%s, %s) = %q, want %q", c.net.Name, c.pkgpath, got, c.url)
		}
	}
}

func TestTopoOrderCycle(t *testing.T) {
	cs := []contract{
		{PkgPath: "a", Deps: []string{"b"}},
		{PkgPath: "b", Deps: []string{"a"}},
	}
	if _, err := topoOrder(cs); err == nil {
		t.Fatal("expected a cycle error")
	}
}

// externalDeps must flag exactly the deps nobody in this run will create.
// Getting this wrong is what let p/archive/dom sink r/moul/demo/importdemo/v2
// at package 122 of 131, with an opaque type-check error instead of a
// prerequisite named before anything was broadcast.
func TestExternalDeps(t *testing.T) {
	mk := func(path string, deps ...string) contract {
		return contract{PkgPath: path, Deps: deps}
	}
	lib := mk("gno.land/p/moul/lib/v1")
	a := mk("gno.land/r/moul/a/v1", "gno.land/p/moul/lib/v1", "gno.land/p/archive/dom", "strings")
	b := mk("gno.land/r/moul/b/v1", "gno.land/p/archive/dom", "gno.land/p/nt/avl/v0")

	ordered := []contract{lib, a, b}
	todo := []plan{{c: lib}, {c: a}, {c: b}}

	got := externalDeps(ordered, todo)
	if len(got) != 2 {
		t.Fatalf("externalDeps = %+v, want 2 entries", got)
	}
	// sorted by path
	if got[0].pkg != "gno.land/p/archive/dom" || got[1].pkg != "gno.land/p/nt/avl/v0" {
		t.Fatalf("order/paths = %+v", got)
	}
	// shared dep lists every dependent, sorted and deduped
	if strings.Join(got[0].neededBy, ",") != "gno.land/r/moul/a/v1,gno.land/r/moul/b/v1" {
		t.Errorf("neededBy = %v", got[0].neededBy)
	}
	// a dep we publish ourselves is NOT external, and stdlib is ignored
	for _, d := range got {
		if d.pkg == "gno.land/p/moul/lib/v1" || d.pkg == "strings" {
			t.Errorf("unexpected entry %q", d.pkg)
		}
	}
}

// A dep that is published by this run must never be reported, even when it is
// only reachable through another package's dep list.
func TestExternalDepsIgnoresSelfPublished(t *testing.T) {
	lib := contract{PkgPath: "gno.land/p/moul/lib/v1"}
	demo := contract{PkgPath: "gno.land/r/moul/demo/v1", Deps: []string{"gno.land/p/moul/lib/v1"}}
	got := externalDeps([]contract{lib, demo}, []plan{{c: lib}, {c: demo}})
	if len(got) != 0 {
		t.Fatalf("externalDeps = %+v, want none", got)
	}
}
