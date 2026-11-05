package main

import (
	"os"
	"path/filepath"
	"testing"
)

func writeMod(t *testing.T, root, dir, body string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Join(root, dir), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, dir, "gnomod.toml"), []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

const onceMod = `module = "gno.land/p/moul/once/v0"
gno = "0.9"

[addpkg]
  creator = "g1manfred47kzduec920z88wfr64ylksmdcedlf5"

[[deployment]]
  chain = "onyx-1"
  path = "gno.land/p/g1magld5ptgzaktqcexxq0pgq5lmdf0kz6re8hlv/once/v0"
  url = "https://onyx.testnets.gno.land/p/g1magld5ptgzaktqcexxq0pgq5lmdf0kz6re8hlv/once/v0"
  revision = "4c02d6d9369d80732665898a5c4a95002c68bfd4"
  at = "2026-11-05T11:10:22Z"

[[deployment]]
  chain = "staging"
  path = "gno.land/p/g1other/once/v0"
  at = "2026-11-05T11:10:22Z"
`

func TestDeployedPath(t *testing.T) {
	root := t.TempDir()
	writeMod(t, root, "p/moul/once", onceMod)

	const pkg = "gno.land/p/moul/once/v0"
	if got := deployedPath(root, "p/moul/once", "onyx-1", pkg); got != "gno.land/p/g1magld5ptgzaktqcexxq0pgq5lmdf0kz6re8hlv/once/v0" {
		t.Errorf("onyx-1: got %q", got)
	}
	// A second row in the same file must not leak into the first chain's answer.
	if got := deployedPath(root, "p/moul/once", "staging", pkg); got != "gno.land/p/g1other/once/v0" {
		t.Errorf("staging: got %q", got)
	}
	// A chain with no row is the ordinary case and must answer empty, so the
	// probe falls back to the canonical path rather than to the wrong chain's.
	if got := deployedPath(root, "p/moul/once", "gnoland-1", pkg); got != "" {
		t.Errorf("mainnet: want empty, got %q", got)
	}
	// The negative that matters most: p/moul/ulist carries v1 in the tree while
	// v0 lives only on chain, and both are contracts with this same Dir. A row
	// belongs to the version the module line declares, never to its sibling.
	if got := deployedPath(root, "p/moul/once", "onyx-1", "gno.land/p/moul/once/v1"); got != "" {
		t.Errorf("sibling version: want empty, got %q", got)
	}
	if got := deployedPath(root, "nope", "onyx-1", pkg); got != "" {
		t.Errorf("missing dir: want empty, got %q", got)
	}
}

func TestDeployedPathIgnoresOtherTables(t *testing.T) {
	root := t.TempDir()
	// `chain` and `path` keys under a DIFFERENT table must not be read as a
	// deployment: the scanner is line based, so table boundaries are the only
	// thing keeping it honest.
	writeMod(t, root, "p/x", `module = "gno.land/p/x/v0"

[somethingelse]
  chain = "onyx-1"
  path = "gno.land/p/wrong/v0"
`)
	if got := deployedPath(root, "p/x", "onyx-1", "gno.land/p/x/v0"); got != "" {
		t.Errorf("want empty, got %q", got)
	}
}
