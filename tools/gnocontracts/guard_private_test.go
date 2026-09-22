package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// privateFixture builds a workspace plus the contracts.json the guard reads its
// exemptions from. Each entry is "<dir>": "<gnomod body>", and the catalog is
// derived from cs, which is keyed by module path.
func privateFixture(t *testing.T, mods map[string]string, cs map[string]Contract) string {
	t.Helper()
	root := t.TempDir()
	writeFile(t, root, "gnowork.toml", "")
	for dir, body := range mods {
		full := filepath.Join(root, filepath.FromSlash(dir))
		if err := os.MkdirAll(full, 0o755); err != nil {
			t.Fatal(err)
		}
		writeFile(t, full, "gnomod.toml", body)
	}
	m := Manifest{Networks: defaultNetworks()}
	for path, c := range cs {
		c.PkgPath = path
		m.Contracts = append(m.Contracts, c)
	}
	b, err := json.Marshal(m)
	if err != nil {
		t.Fatal(err)
	}
	writeFile(t, root, manifestFile, string(b))
	return root
}

func mod(path string, extra ...string) string {
	return "module = \"" + path + "\"\ngno = \"0.9\"\n" + strings.Join(extra, "")
}

func TestGuardPrivateRequiresAnAnswerFromEveryUndeployedRealm(t *testing.T) {
	root := privateFixture(t, map[string]string{
		"r/moul/silent": mod("gno.land/r/moul/silent/v0"),
	}, nil)
	err := cmdGuardPrivate(root)
	if err == nil {
		t.Fatal("a realm declaring neither private nor a reason was accepted")
	}
	if !strings.Contains(err.Error(), "r/moul/silent") {
		t.Fatalf("failure does not name the realm: %v", err)
	}

	root = privateFixture(t, map[string]string{
		"r/moul/priv": mod("gno.land/r/moul/priv/v0", "private = true\n"),
	}, nil)
	if err := cmdGuardPrivate(root); err != nil {
		t.Fatalf("private realm rejected: %v", err)
	}
}

func TestGuardPrivateOptOutNeedsARealReason(t *testing.T) {
	root := privateFixture(t, map[string]string{
		"r/moul/pub": mod("gno.land/r/moul/pub/v0", "\n# public: imported by r/moul/x/other, which is the point\n"),
	}, nil)
	if err := cmdGuardPrivate(root); err != nil {
		t.Fatalf("opt-out with a reason rejected: %v", err)
	}

	// "why not" is not a reason, and neither is a bare marker.
	root = privateFixture(t, map[string]string{
		"r/moul/pub": mod("gno.land/r/moul/pub/v0", "\n# public: why not\n"),
	}, nil)
	err := cmdGuardPrivate(root)
	if err == nil {
		t.Fatal("a one-clause opt-out reason was accepted")
	}
	if !strings.Contains(err.Error(), "under the") {
		t.Fatalf("failure does not explain the minimum: %v", err)
	}
}

func TestGuardPrivateRefusesItOnAPackage(t *testing.T) {
	// The chain says "private packages must be realm packages"; the guard says
	// it a deploy earlier.
	root := privateFixture(t, map[string]string{
		"p/moul/lib": mod("gno.land/p/moul/lib/v0", "private = true\n"),
	}, nil)
	err := cmdGuardPrivate(root)
	if err == nil {
		t.Fatal("a p/ package declaring private was accepted")
	}
	if !strings.Contains(err.Error(), "only realms may") {
		t.Fatalf("failure does not say why: %v", err)
	}

	// `private = false` is the same statement, and just as refused.
	root = privateFixture(t, map[string]string{
		"p/moul/lib": mod("gno.land/p/moul/lib/v0", "private = false\n"),
	}, nil)
	if err := cmdGuardPrivate(root); err == nil {
		t.Fatal("a p/ package declaring private = false was accepted")
	}
}

func TestGuardPrivateDoesNotAskRealmsWhoseDoorIsShut(t *testing.T) {
	// Live on mainnet: the chain answered and will not take another answer.
	root := privateFixture(t,
		map[string]string{"r/moul/live": mod("gno.land/r/moul/live/v0")},
		map[string]Contract{"gno.land/r/moul/live/v0": {
			Published: map[string]Pub{"mainnet": {Uploaded: true}},
		}})
	if err := cmdGuardPrivate(root); err != nil {
		t.Fatalf("realm already live on mainnet was asked anyway: %v", err)
	}

	// Live only on a testnet: mainnet is still open, so the question stands.
	root = privateFixture(t,
		map[string]string{"r/moul/pearlonly": mod("gno.land/r/moul/pearlonly/v0")},
		map[string]Contract{"gno.land/r/moul/pearlonly/v0": {
			Published: map[string]Pub{"pearl": {Uploaded: true}},
		}})
	if err := cmdGuardPrivate(root); err == nil {
		t.Fatal("realm live only on pearl was let through; mainnet is still open")
	}

	// A byte-for-byte mirror of the monorepo's copy: editing its gnomod would
	// make `make sync` read the edit as upstream drift.
	root = privateFixture(t,
		map[string]string{"r/moul/mirror": mod("gno.land/r/moul/mirror/v0")},
		map[string]Contract{"gno.land/r/moul/mirror/v0": {
			Upstream: "gno.land/r/moul/mirror", UpstreamMatch: "exact",
		}})
	if err := cmdGuardPrivate(root); err != nil {
		t.Fatalf("monorepo mirror was asked to change its frozen gnomod: %v", err)
	}

	// Archived: the toolchain skips it everywhere else too.
	root = privateFixture(t,
		map[string]string{"r/moul/old": mod("gno.land/r/moul/old/v0", "ignore = true\n")},
		nil)
	if err := cmdGuardPrivate(root); err != nil {
		t.Fatalf("archived realm was asked: %v", err)
	}
}
