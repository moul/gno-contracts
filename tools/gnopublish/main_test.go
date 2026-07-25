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

func TestTxHash(t *testing.T) {
	// raw bytes -> full base64 (never truncated at a non-printable byte).
	got := txHash([]byte{0x00, 0xff, 0x10, 0x20})
	if got != "AP8QIA==" {
		t.Fatalf("txHash = %q, want AP8QIA==", got)
	}
}

func TestMdLink(t *testing.T) {
	u := "https://gno.land/r/moul/hello/v1"
	if got := mdLink(u); got != "["+u+"]("+u+")" {
		t.Fatalf("mdLink = %q", got)
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
