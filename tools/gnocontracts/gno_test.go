package main

import (
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
)

func mkpkg(t *testing.T, root, dir, module, extra string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Join(root, dir), 0o755); err != nil {
		t.Fatal(err)
	}
	writeFile(t, filepath.Join(root, dir), "gnomod.toml", "module = \""+module+"\"\ngno = \"0.9\"\n"+extra)
	writeFile(t, filepath.Join(root, dir), "x.gno", "package x\n")
}

// An archived package must never reach the toolchain. gno skips an
// `ignore = true` module for `lint` but builds it anyway for a `test` that
// names it, and a package is archived precisely because it no longer builds, so
// a missing filter here is a red CI rather than a skip.
func TestContractDirsDropsArchived(t *testing.T) {
	root := t.TempDir()
	writeFile(t, root, "gnowork.toml", "")
	writeFile(t, root, "gnomod.lock", "lock = 1\n")
	mkpkg(t, root, "p/moul/live", "gno.land/p/moul/live/v0", "")
	mkpkg(t, root, "r/moul/old", "gno.land/r/moul/old/v0", "ignore = true\n")

	got, err := contractDirs(root, true)
	if err != nil {
		t.Fatal(err)
	}
	if !slices.Equal(got, []string{"p/moul/live"}) {
		t.Fatalf("contractDirs = %v, want only the live package", got)
	}
}

// fmt rewrites files in place, and a superseded version is a read-only copy of
// history: reformatting one would make `gnopm verify` fail against the hash it
// recorded. So only lint and test see them.
func TestContractDirsOrdersTreeBeforeAssembly(t *testing.T) {
	root := t.TempDir()
	writeFile(t, root, "gnowork.toml", "")
	writeFile(t, root, "gnomod.lock", "lock = 1\n\n[[module]]\nmodule = \"gno.land/p/moul/gone/v0\"\nsource = { commit = \"deadbeef\", dir = \"p/moul/gone\" }\nhash = \"h1:0000000000000000000000000000000000000000000=\"\n")
	mkpkg(t, root, "p/moul/live", "gno.land/p/moul/live/v0", "")
	mkpkg(t, root, ".gnopm/gno.land/p/moul/gone/v0", "gno.land/p/moul/gone/v0", "")

	with, err := contractDirs(root, true)
	if err != nil {
		t.Fatal(err)
	}
	without, err := contractDirs(root, false)
	if err != nil {
		t.Fatal(err)
	}
	if !slices.Equal(without, []string{"p/moul/live"}) {
		t.Fatalf("contractDirs(superseded=false) = %v, want the working tree only", without)
	}
	if len(with) != 2 || with[0] != "p/moul/live" {
		t.Fatalf("contractDirs(superseded=true) = %v, want the working tree first", with)
	}
}

func TestSelectDirs(t *testing.T) {
	dirs := []string{"p/moul/x/daily/b58", "r/moul/x/daily/b58demo", "r/moul/home"}
	for _, tc := range []struct {
		sel  []string
		want []string
	}{
		{[]string{"b58"}, []string{"p/moul/x/daily/b58", "r/moul/x/daily/b58demo"}},
		{[]string{"./r/moul/home"}, []string{"r/moul/home"}}, // the shape make passes through
		{[]string{"r/moul/home/"}, []string{"r/moul/home"}},
		{[]string{"nothing"}, nil},
		{[]string{"home", "b58demo"}, []string{"r/moul/x/daily/b58demo", "r/moul/home"}},
	} {
		if got := selectDirs(dirs, tc.sel); !slices.Equal(got, tc.want) {
			t.Errorf("selectDirs(%v) = %v, want %v", tc.sel, got, tc.want)
		}
	}
}

// The view is what makes a build here reproducible: gno resolves a gno.land/*
// import from GNOROOT/examples first, so an examples/ that is not empty means
// lint and test silently read the monorepo checkout instead of vendor/.
func TestEnsureViewEmptiesExamples(t *testing.T) {
	gnoroot := t.TempDir()
	for _, d := range []string{"gnovm", "examples", ".git"} {
		if err := os.MkdirAll(filepath.Join(gnoroot, d), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	writeFile(t, filepath.Join(gnoroot, "examples"), "marker", "from the monorepo")
	root := t.TempDir()
	t.Setenv("GNOROOT", gnoroot)

	view, err := ensureView(root)
	if err != nil {
		t.Fatal(err)
	}
	if entries, err := os.ReadDir(filepath.Join(view, "examples")); err != nil || len(entries) != 0 {
		t.Fatalf("view examples/ = %v (err %v), want empty", entries, err)
	}
	if _, err := os.Stat(filepath.Join(view, "gnovm")); err != nil {
		t.Fatalf("view is missing gnovm: %v", err)
	}
	if _, err := os.Lstat(filepath.Join(view, ".git")); err == nil {
		t.Fatal("view carries .git; dot-entries of the checkout are not part of the toolchain")
	}
}

// Building the view out of itself leaves gnodev dying on `failed loading stdlib
// "errors": does not exist`. It happened in CI while the view was the
// Makefile's job and GNOROOT was a workflow step's, so it is an error now.
func TestEnsureViewRefusesItself(t *testing.T) {
	root := t.TempDir()
	t.Setenv("GNOROOT", filepath.Join(root, viewDir))
	if _, err := ensureView(root); err == nil {
		t.Fatal("ensureView accepted the view as GNOROOT")
	}
	t.Setenv("GNOROOT", "")
	if _, err := ensureView(root); err == nil {
		t.Fatal("ensureView accepted an unset GNOROOT")
	}
}

// gnopm discovers the chain from the package path, so gno.land/... means
// MAINNET unless told otherwise. An unknown network name must therefore fail
// loudly: the $(shell) this replaced could not fail a make run, so a typo
// expanded to nothing and produced a mainnet broadcast script.
func TestLookupNetworkRejectsUnknown(t *testing.T) {
	root := t.TempDir()
	n, err := lookupNetwork(root, "pearl")
	if err != nil {
		t.Fatal(err)
	}
	if n.ChainID != "pearl-1" {
		t.Fatalf("lookupNetwork(pearl).ChainID = %q", n.ChainID)
	}
	_, err = lookupNetwork(root, "perl")
	if err == nil {
		t.Fatal("lookupNetwork accepted an unknown network")
	}
	for _, want := range []string{"perl", "mainnet", "pearl"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("error %q does not name %q", err, want)
		}
	}
}
