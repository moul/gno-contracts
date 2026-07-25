package main

import "testing"

func TestMatchesAny(t *testing.T) {
	cases := []struct {
		dir  string
		sels []string
		want bool
	}{
		{"p/moul/hello/v1", []string{"./..."}, true},
		{"p/moul/hello/v1", []string{"./p/moul/hello"}, true},   // all versions
		{"p/moul/hello/v2", []string{"./p/moul/hello"}, true},   // all versions
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

func TestTopoOrderCycle(t *testing.T) {
	cs := []contract{
		{PkgPath: "a", Deps: []string{"b"}},
		{PkgPath: "b", Deps: []string{"a"}},
	}
	if _, err := topoOrder(cs); err == nil {
		t.Fatal("expected a cycle error")
	}
}
