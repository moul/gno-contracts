package main

import (
	"os"
	"path/filepath"
	"testing"
)

var testNet = network{Name: "mainnet", ChainID: "gnoland-1", RPC: "https://rpc.gno.land:443"}

func TestCacheRoundTrip(t *testing.T) {
	root := t.TempDir()
	c := loadCache(root, testNet, false)
	c.record("gno.land/p/moul/md/v0", "")
	c.record("gno.land/p/moul/fifo/v0", "abc")
	if err := c.save(); err != nil {
		t.Fatal(err)
	}

	back := loadCache(root, testNet, false)
	for _, tc := range []struct {
		pkg      string
		wantOK   bool
		wantHash string
	}{
		{"gno.land/p/moul/md/v0", true, ""},
		{"gno.land/p/moul/fifo/v0", true, "abc"},
		{"gno.land/p/moul/never/v0", false, ""},
	} {
		e, ok := back.onChain(tc.pkg)
		if ok != tc.wantOK || e.Hash != tc.wantHash {
			t.Errorf("%s: got (%v, %q), want (%v, %q)", tc.pkg, ok, e.Hash, tc.wantOK, tc.wantHash)
		}
		if ok && e.CheckedAt == "" {
			t.Errorf("%s: checked_at not recorded", tc.pkg)
		}
	}
}

// A cache written for another chain id (e.g. a testnet reset under the same
// name) must not leak "on chain" facts into this one.
func TestCacheIgnoresOtherChainID(t *testing.T) {
	root := t.TempDir()
	old := loadCache(root, testNet, false)
	old.record("gno.land/p/moul/md/v0", "")
	old.save()

	// Same file name, different chain id recorded inside.
	b, _ := os.ReadFile(old.path)
	os.WriteFile(old.path, []byte(string(b[:0])+replaceOnce(string(b), `"gnoland-1"`, `"gnoland1"`)), 0o644)

	if _, ok := loadCache(root, testNet, false).onChain("gno.land/p/moul/md/v0"); ok {
		t.Fatal("entries from a different chain id must be discarded")
	}
}

func TestCacheCorruptFileStartsEmpty(t *testing.T) {
	root := t.TempDir()
	c := loadCache(root, testNet, false)
	os.MkdirAll(filepath.Dir(c.path), 0o755)
	os.WriteFile(c.path, []byte("{not json"), 0o644)
	if len(loadCache(root, testNet, false).Entries) != 0 {
		t.Fatal("a corrupt cache must be treated as empty, not as an error")
	}
}

func TestCacheHashRules(t *testing.T) {
	c := loadCache(t.TempDir(), testNet, false)
	const pkg = "gno.land/p/moul/md/v0"

	c.record(pkg, "h1")
	c.record(pkg, "") // existence-only re-check must not downgrade
	if !c.contentVerified(pkg, "h1") {
		t.Error("existence-only record downgraded a verified hash")
	}
	if c.contentVerified(pkg, "h2") {
		t.Error("a changed local hash must not count as verified")
	}
	if c.contentVerified(pkg, "") {
		t.Error("an empty hash must never count as verified")
	}

	c.forgetHash(pkg)
	if c.contentVerified(pkg, "h1") {
		t.Error("forgetHash must drop the verification")
	}
	if _, ok := c.onChain(pkg); !ok {
		t.Error("forgetHash must keep the existence fact")
	}
}

func TestCacheDisabled(t *testing.T) {
	root := t.TempDir()
	c := loadCache(root, testNet, true)
	c.record("gno.land/p/moul/md/v0", "")
	if _, ok := c.onChain("gno.land/p/moul/md/v0"); ok {
		t.Error("-no-cache must not answer from cache")
	}
	if err := c.save(); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(c.path); !os.IsNotExist(err) {
		t.Error("-no-cache must not write the cache file")
	}
}

func TestSaveOnlyWhenDirty(t *testing.T) {
	root := t.TempDir()
	c := loadCache(root, testNet, false)
	c.save()
	if _, err := os.Stat(c.path); !os.IsNotExist(err) {
		t.Error("an unchanged cache must not be written")
	}
}

func TestLocalHash(t *testing.T) {
	dir := t.TempDir()
	write := func(name, body string) {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	write("gnomod.toml", "module = \"gno.land/p/moul/hashme/v0\"\ngno = \"0.9\"\n")
	write("hashme.gno", "package hashme\n\nfunc A() int { return 1 }\n")

	h1, err := localHash(dir, "gno.land/p/moul/hashme/v0")
	if err != nil {
		t.Fatal(err)
	}
	if len(h1) != 64 {
		t.Fatalf("want a hex sha256, got %q", h1)
	}

	// Test files never reach the chain, so they must not change the hash.
	write("hashme_test.gno", "package hashme\n")
	if h2, _ := localHash(dir, "gno.land/p/moul/hashme/v0"); h2 != h1 {
		t.Error("adding a _test.gno changed the hash")
	}

	// Production content does.
	write("hashme.gno", "package hashme\n\nfunc A() int { return 2 }\n")
	if h3, _ := localHash(dir, "gno.land/p/moul/hashme/v0"); h3 == h1 {
		t.Error("changing production code did not change the hash")
	}
}

func replaceOnce(s, old, new string) string {
	for i := 0; i+len(old) <= len(s); i++ {
		if s[i:i+len(old)] == old {
			return s[:i] + new + s[i+len(old):]
		}
	}
	return s
}
