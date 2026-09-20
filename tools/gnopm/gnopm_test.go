package main

import (
	"bytes"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// --- format -----------------------------------------------------------------

func TestLockRoundTrip(t *testing.T) {
	src := &Lock{Format: lockFormat, Modules: []LockEntry{
		{Module: "gno.land/p/moul/md/v1", Source: Source{Dir: "p/moul/md"}},
		{Module: "gno.land/p/moul/md/v0", Source: Source{Commit: strings.Repeat("a", 40), Dir: "p/moul/md/v0"}, Hash: "h1:abc="},
		{Module: "gno.land/r/moul/home/v0", Source: Source{Dir: "r/moul/home"}},
	}}
	text := src.String()
	got, err := parseLock(text)
	if err != nil {
		t.Fatalf("parse: %v", err)
	}
	if again := got.String(); again != text {
		t.Fatalf("round trip is not byte-stable:\n--- first ---\n%s\n--- second ---\n%s", text, again)
	}
	if len(got.Modules) != 3 {
		t.Fatalf("got %d modules, want 3", len(got.Modules))
	}
	// Sorted by module path, so a regenerated lock never reorders.
	if got.Modules[0].Module != "gno.land/p/moul/md/v0" {
		t.Fatalf("not sorted: first is %q", got.Modules[0].Module)
	}
	if got.Modules[0].Source.Variant() != "commit" || got.Modules[1].Source.Variant() != "dir" {
		t.Fatalf("variants lost in round trip")
	}
}

func TestParseLockRejects(t *testing.T) {
	good := "lock = 1\n\n[[module]]\nmodule = \"gno.land/p/a/v0\"\nsource = { dir = \"p/a\" }\n"
	if _, err := parseLock(good); err != nil {
		t.Fatalf("the good case must parse: %v", err)
	}
	for _, tc := range []struct{ name, in, want string }{
		{"no format", "[[module]]\nmodule = \"gno.land/p/a/v0\"\nsource = { dir = \"p/a\" }\n", "format declaration"},
		{"future format", "lock = 99\n", "upgrade gnopm"},
		{"unknown top key", "nope = 1\n", "unknown top-level key"},
		{"unknown entry key", "lock = 1\n[[module]]\nmodule = \"m\"\nsource = { dir = \"d\" }\nnope = \"x\"\n", "unknown key"},
		{"dir with hash", "lock = 1\n[[module]]\nmodule = \"m\"\nsource = { dir = \"d\" }\nhash = \"h1:x\"\n", "must not carry a hash"},
		{"commit without hash", "lock = 1\n[[module]]\nmodule = \"m\"\nsource = { commit = \"" + strings.Repeat("a", 40) + "\", dir = \"d\" }\n", "must carry a hash"},
		{"commit without dir", "lock = 1\n[[module]]\nmodule = \"m\"\nsource = { commit = \"" + strings.Repeat("a", 40) + "\" }\nhash = \"h1:x\"\n", "no dir"},
		{"short commit", "lock = 1\n[[module]]\nmodule = \"m\"\nsource = { commit = \"abc\", dir = \"d\" }\nhash = \"h1:x\"\n", "too short"},
		{"duplicate module", "lock = 1\n[[module]]\nmodule = \"m\"\nsource = { dir = \"a\" }\n[[module]]\nmodule = \"m\"\nsource = { dir = \"b\" }\n", "duplicate entry"},
		{"empty source", "lock = 1\n[[module]]\nmodule = \"m\"\nsource = {  }\n", "empty inline table"},
		{"unquoted", "lock = 1\n[[module]]\nmodule = m\nsource = { dir = \"d\" }\n", "quoted string"},
		{"not implemented: chain", "lock = 1\n[[module]]\nmodule = \"m\"\nsource = { chain = \"gnoland-1\", tx = \"abc\" }\nhash = \"h1:x\"\n", "not implemented"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			_, err := parseLock(tc.in)
			if err == nil {
				t.Fatalf("expected an error mentioning %q, got none", tc.want)
			}
			if !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("error %q does not mention %q", err, tc.want)
			}
		})
	}
}

// --- hashing ----------------------------------------------------------------

// TestHashGolden pins the algorithm to a constant.
//
// The construction is Go's dirhash Hash1: sha256 over a sorted manifest of
// "<sha256 of content>  <name>\n" lines. Pinning one vector means a future
// refactor that quietly changes the hash fails here rather than silently
// invalidating every lock in the wild.
func TestHashGolden(t *testing.T) {
	dir := t.TempDir()
	write(t, filepath.Join(dir, "a.gno"), "package a\n")
	write(t, filepath.Join(dir, "gnomod.toml"), "module = \"gno.land/p/x/a/v0\"\n")
	got, err := hashDirFiles(dir, []string{"a.gno", "gnomod.toml"})
	if err != nil {
		t.Fatal(err)
	}
	// Computed independently of this code, from the documented construction:
	//   sha256( concat over sorted names of "<sha256(content) hex>  <name>\n" )
	// base64-encoded and prefixed. If this constant has to change, the lock
	// format has changed and every gnomod.lock in existence needs regenerating.
	const want = "h1:L5FhBicosFETI1RZ4bQD389srcguWIBD1ZZoNlxqtIY="
	if got != want {
		t.Fatalf("h1 construction changed:\n got: %s\nwant: %s", got, want)
	}
	// Order must not matter: the function sorts.
	rev, err := hashDirFiles(dir, []string{"gnomod.toml", "a.gno"})
	if err != nil {
		t.Fatal(err)
	}
	if rev != got {
		t.Fatalf("hash depends on input order: %s vs %s", got, rev)
	}
	// Content must matter.
	write(t, filepath.Join(dir, "a.gno"), "package a // changed\n")
	after, err := hashDirFiles(dir, []string{"a.gno", "gnomod.toml"})
	if err != nil {
		t.Fatal(err)
	}
	if after == got {
		t.Fatal("hash did not change when content did")
	}
	// The file NAME must matter, not just the bytes.
	dir2 := t.TempDir()
	write(t, filepath.Join(dir2, "b.gno"), "package a\n")
	write(t, filepath.Join(dir2, "gnomod.toml"), "module = \"gno.land/p/x/a/v0\"\n")
	renamed, err := hashDirFiles(dir2, []string{"b.gno", "gnomod.toml"})
	if err != nil {
		t.Fatal(err)
	}
	if renamed == got {
		t.Fatal("hash ignores file names")
	}
}

// --- module paths -----------------------------------------------------------

func TestSplitVersion(t *testing.T) {
	for _, tc := range []struct {
		in   string
		base string
		n    int
		ok   bool
	}{
		{"gno.land/p/moul/md/v0", "gno.land/p/moul/md", 0, true},
		{"gno.land/p/moul/md/v12", "gno.land/p/moul/md", 12, true},
		{"gno.land/p/moul/x/amm/v2", "gno.land/p/moul/x/amm", 2, true},
		{"gno.land/p/moul/md", "", 0, false},
		{"gno.land/p/moul/md/vx", "", 0, false},
		{"nope", "", 0, false},
	} {
		base, n, ok := splitVersion(tc.in)
		if ok != tc.ok || base != tc.base || n != tc.n {
			t.Errorf("splitVersion(%q) = (%q,%d,%v), want (%q,%d,%v)", tc.in, base, n, ok, tc.base, tc.n, tc.ok)
		}
	}
}

func TestSetModuleLinePreservesTheFile(t *testing.T) {
	dir := t.TempDir()
	p := filepath.Join(dir, "gnomod.toml")
	const before = "# a comment worth keeping\nmodule = \"gno.land/p/moul/md/v0\"\ngno = \"0.9\"\nignore = false\n"
	write(t, p, before)
	if err := setModuleLine(p, "gno.land/p/moul/md/v1"); err != nil {
		t.Fatal(err)
	}
	got := read(t, p)
	want := strings.Replace(before, "/v0", "/v1", 1)
	if got != want {
		t.Fatalf("setModuleLine rewrote more than the module line:\n got: %q\nwant: %q", got, want)
	}
}

func TestMatchDestPrefersTheLongestMatch(t *testing.T) {
	// Package directories nest: p/moul/x/amm/v0 lives inside p/moul/x. A
	// shortest-prefix match would file the nested package's files under its
	// ancestor's destination.
	dests := map[string]string{"p/moul/x": "/out/ancestor", "p/moul/x/amm/v0": "/out/amm"}
	src, rel, ok := matchDest("p/moul/x/amm/v0/amm.gno", dests)
	if !ok || src != "p/moul/x/amm/v0" || rel != "amm.gno" {
		t.Fatalf("got (%q,%q,%v), want the nested package", src, rel, ok)
	}
	if _, _, ok := matchDest("p/other/thing.gno", dests); ok {
		t.Fatal("matched a path outside every destination")
	}
}

// --- end to end, against a real git repository -------------------------------

// TestLifecycle drives the whole thing over a throwaway git repository:
// lock, freeze, bump, install, verify. It is the only test that proves the
// load-bearing claim, that a version deleted from the working tree is still
// resolvable, because that claim is about git, not about Go.
func TestLifecycle(t *testing.T) {
	root := newRepo(t)

	// Two packages, md/v0 and a realm that imports it.
	addPkg(t, root, "p/moul/md/v0", "gno.land/p/moul/md/v0", "package md\n\nfunc H1(s string) string { return \"# \" + s }\n")
	addPkg(t, root, "r/moul/home/v0", "gno.land/r/moul/home/v0", "package home\n")
	commit(t, root, "seed")

	mustRun(t, root, "sync")
	l := mustLock(t, root)
	if len(l.Modules) != 2 {
		t.Fatalf("lock has %d modules, want 2", len(l.Modules))
	}
	for _, e := range l.Modules {
		if !e.Source.InTree() {
			t.Fatalf("%s should be a tree entry, got %s", e.Module, e.Source.Variant())
		}
	}
	mustRun(t, root, "verify")

	// Bump md to v1 in place. The directory does not move.
	before := read(t, filepath.Join(root, "p/moul/md/v0/md.gno"))
	mustRun(t, root, "bump", "p/moul/md/v0")
	if after := read(t, filepath.Join(root, "p/moul/md/v0/md.gno")); after != before {
		t.Fatal("bump rewrote source; it must only touch the module line")
	}
	mod, _, err := readGnomod(filepath.Join(root, "p/moul/md/v0/gnomod.toml"))
	if err != nil {
		t.Fatal(err)
	}
	if mod != "gno.land/p/moul/md/v1" {
		t.Fatalf("module line is %q, want the v1 path", mod)
	}
	l = mustLock(t, root)
	if len(l.Modules) != 3 {
		t.Fatalf("after bump the lock has %d modules, want 3 (md v0 pinned, md v1 in tree, home v0)", len(l.Modules))
	}
	v0, ok, _ := findModule(l, "gno.land/p/moul/md/v0")
	if !ok || v0.Source.Variant() != "commit" || v0.Hash == "" {
		t.Fatalf("md/v0 should be pinned to a commit with a hash, got %+v", v0)
	}
	v1, ok, _ := findModule(l, "gno.land/p/moul/md/v1")
	if !ok || !v1.Source.InTree() || v1.Hash != "" {
		t.Fatalf("md/v1 should be an unhashed tree entry, got %+v", v1)
	}

	// The v1 edit that a reviewer is supposed to be able to see.
	write(t, filepath.Join(root, "p/moul/md/v0/md.gno"), "package md\n\nfunc H1(s string) string { return \"# \" + s + \"\\n\" }\n")

	// v0 is gone from the tree, so install has to reconstruct it.
	var out bytes.Buffer
	if err := install(testEnv(root, &out)); err != nil {
		t.Fatalf("install: %v\n%s", err, out.String())
	}
	got := read(t, filepath.Join(root, ".gnopm/gno.land/p/moul/md/v0/md.gno"))
	if got != before {
		t.Fatalf("materialized v0 is not the committed v0:\n got: %q\nwant: %q", got, before)
	}
	gotMod, _, err := readGnomod(filepath.Join(root, ".gnopm/gno.land/p/moul/md/v0/gnomod.toml"))
	if err != nil {
		t.Fatal(err)
	}
	if gotMod != "gno.land/p/moul/md/v0" {
		t.Fatalf("materialized package declares %q, want the v0 path", gotMod)
	}

	// Second install is a no-op via the stamp, and says nothing at all:
	// a command that is safe to run constantly has to be silent when there
	// is nothing to report, or the output becomes noise people stop reading.
	out.Reset()
	if err := install(testEnv(root, &out)); err != nil {
		t.Fatal(err)
	}
	if out.String() != "" {
		t.Fatalf("second install should have been silent, said: %q", out.String())
	}

	// Tampering with the assembly is caught and repaired.
	write(t, filepath.Join(root, ".gnopm/gno.land/p/moul/md/v0/md.gno"), "package md // tampered\n")
	os.Remove(filepath.Join(root, ".gnopm", stampFile))
	out.Reset()
	if err := install(testEnv(root, &out)); err != nil {
		t.Fatalf("install after tampering: %v", err)
	}
	if read(t, filepath.Join(root, ".gnopm/gno.land/p/moul/md/v0/md.gno")) != before {
		t.Fatal("install did not repair a tampered assembly")
	}

	// Pruning: an entry that leaves the lock leaves the assembly.
	commit(t, root, "md v1")
	l = mustLock(t, root)
	kept := &Lock{Format: lockFormat}
	for _, e := range l.Modules {
		if e.Module != "gno.land/p/moul/md/v0" {
			kept.Modules = append(kept.Modules, e)
		}
	}
	if err := writeLock(root, kept); err != nil {
		t.Fatal(err)
	}
	out.Reset()
	if err := install(testEnv(root, &out)); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(root, ".gnopm/gno.land/p/moul/md/v0")); !os.IsNotExist(err) {
		t.Fatal("install did not prune a module the lock dropped")
	}
}

// TestVerifyCatchesAStaleLock is the CI guard's own test: adding a package
// without re-locking must fail, and must say so in words.
func TestVerifyCatchesAStaleLock(t *testing.T) {
	root := newRepo(t)
	addPkg(t, root, "p/moul/a/v0", "gno.land/p/moul/a/v0", "package a\n")
	commit(t, root, "seed")
	mustRun(t, root, "sync")

	addPkg(t, root, "p/moul/b/v0", "gno.land/p/moul/b/v0", "package b\n")
	commit(t, root, "add b")
	err := verify(testEnv(root, &bytes.Buffer{}))
	if err == nil {
		t.Fatal("verify passed on a stale lock")
	}
	if !strings.Contains(err.Error(), "is stale") || !strings.Contains(err.Error(), "gnopm sync") {
		t.Fatalf("verify's error does not say what to do: %v", err)
	}
}

// TestVerifyCatchesRewrittenHistory: if the commit a version is pinned to no
// longer holds what the hash promises, every materialization would be wrong,
// so verify has to refuse rather than warn.
func TestVerifyCatchesRewrittenHistory(t *testing.T) {
	root := newRepo(t)
	addPkg(t, root, "p/moul/a/v0", "gno.land/p/moul/a/v0", "package a\n")
	commit(t, root, "seed")
	mustFreeze(t, root)
	l := mustLock(t, root)
	l.Modules[0].Hash = "h1:deliberatelyWrong="
	if err := writeLock(root, l); err != nil {
		t.Fatal(err)
	}
	var out bytes.Buffer
	err := verify(testEnv(root, &out))
	if err == nil {
		t.Fatal("verify passed on a hash that does not reproduce")
	}
	if !strings.Contains(err.Error(), "do not reproduce") {
		t.Fatalf("unexpected error: %v", err)
	}
	if !strings.Contains(out.String(), "gno.land/p/moul/a/v0") {
		t.Fatalf("verify did not name the offending module: %s", out.String())
	}
}

// TestFreezeThenMove is the migration in miniature, and the property the whole
// de-versioning change rests on: freeze, move the directory, re-lock, and the
// old version is still byte-identical when materialized.
func TestFreezeThenMove(t *testing.T) {
	root := newRepo(t)
	addPkg(t, root, "p/moul/md/v0", "gno.land/p/moul/md/v0", "package md\n\nfunc A() {}\n")
	addPkg(t, root, "p/moul/md/v1", "gno.land/p/moul/md/v1", "package md\n\nfunc A() {}\nfunc B() {}\n")
	commit(t, root, "seed two versions")
	v0Before := read(t, filepath.Join(root, "p/moul/md/v0/md.gno"))

	mustFreeze(t, root)

	// Step 3 of the migration: the highest version moves up to the
	// unversioned directory, the rest are deleted.
	gitCmd(t, root, "rm", "-r", "-q", "p/moul/md/v0")
	gitCmd(t, root, "mv", "p/moul/md/v1/gnomod.toml", "p/moul/md/gnomod.toml")
	gitCmd(t, root, "mv", "p/moul/md/v1/md.gno", "p/moul/md/md.gno")
	commit(t, root, "de-version md")

	mustRun(t, root, "sync")
	l := mustLock(t, root)
	if len(l.Modules) != 2 {
		t.Fatalf("lock has %d modules, want 2", len(l.Modules))
	}
	v1, _, _ := findModule(l, "gno.land/p/moul/md/v1")
	if v1.Source.Dir != "p/moul/md" || !v1.Source.InTree() {
		t.Fatalf("v1 should now be the tree copy at the unversioned dir, got %+v", v1.Source)
	}
	v0, ok, _ := findModule(l, "gno.land/p/moul/md/v0")
	if !ok || v0.Source.Variant() != "commit" {
		t.Fatalf("v0 should have survived as a history pin, got %+v", v0)
	}

	if err := install(testEnv(root, &bytes.Buffer{})); err != nil {
		t.Fatal(err)
	}
	if got := read(t, filepath.Join(root, ".gnopm/gno.land/p/moul/md/v0/md.gno")); got != v0Before {
		t.Fatalf("v0 did not survive the move:\n got: %q\nwant: %q", got, v0Before)
	}
	if err := verify(testEnv(root, &bytes.Buffer{})); err != nil {
		t.Fatalf("verify after migration: %v", err)
	}
}

func TestBumpRefusesUncommittedSource(t *testing.T) {
	root := newRepo(t)
	addPkg(t, root, "p/moul/a/v0", "gno.land/p/moul/a/v0", "package a\n")
	commit(t, root, "seed")
	write(t, filepath.Join(root, "p/moul/a/v0/a.gno"), "package a // uncommitted\n")
	err := bump(testEnv(root, &bytes.Buffer{}), "p/moul/a/v0", 0, false)
	if err == nil {
		t.Fatal("bump ran on a dirty tree")
	}
	if !strings.Contains(err.Error(), "uncommitted") || !strings.Contains(err.Error(), "-force") {
		t.Fatalf("the error should explain the constraint and the escape hatch: %v", err)
	}
}

func TestScanRejectsDuplicateModules(t *testing.T) {
	root := newRepo(t)
	addPkg(t, root, "p/moul/a/v0", "gno.land/p/moul/a/v0", "package a\n")
	addPkg(t, root, "p/moul/copy", "gno.land/p/moul/a/v0", "package a\n")
	_, err := scanPackages(root)
	if err == nil || !strings.Contains(err.Error(), "two packages declare") {
		t.Fatalf("a duplicate module path must be rejected, got %v", err)
	}
}

func TestScanSkipsVendorAndAssembly(t *testing.T) {
	root := newRepo(t)
	addPkg(t, root, "p/moul/a/v0", "gno.land/p/moul/a/v0", "package a\n")
	addPkg(t, root, "vendor/gno.land/p/nt/avl/v0", "gno.land/p/nt/avl/v0", "package avl\n")
	addPkg(t, root, ".gnopm/gno.land/p/moul/old/v0", "gno.land/p/moul/old/v0", "package old\n")
	pkgs, err := scanPackages(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(pkgs) != 1 || pkgs[0].Module != "gno.land/p/moul/a/v0" {
		t.Fatalf("scan should see only the owned tree package, got %+v", pkgs)
	}
}

// --- helpers ----------------------------------------------------------------

func newRepo(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	write(t, filepath.Join(root, workspaceMarker), "")
	write(t, filepath.Join(root, ".gitignore"), "/"+assemblyDir+"/\n")
	gitCmd(t, root, "init", "-q", "-b", "main")
	gitCmd(t, root, "config", "user.email", "t@example.com")
	gitCmd(t, root, "config", "user.name", "t")
	gitCmd(t, root, "config", "commit.gpgsign", "false")
	return root
}

func addPkg(t *testing.T, root, dir, module, body string) {
	t.Helper()
	write(t, filepath.Join(root, dir, "gnomod.toml"), "module = \""+module+"\"\ngno = \"0.9\"\n")
	name := filepath.Base(strings.TrimSuffix(strings.TrimSuffix(module, "/v0"), "/v1"))
	write(t, filepath.Join(root, dir, name+".gno"), body)
}

func commit(t *testing.T, root, msg string) {
	t.Helper()
	gitCmd(t, root, "add", "-A")
	gitCmd(t, root, "commit", "-q", "-m", msg)
}

func gitCmd(t *testing.T, root string, args ...string) {
	t.Helper()
	cmd := exec.Command("git", args...)
	cmd.Dir = root
	cmd.Env = append(os.Environ(), "GIT_CONFIG_GLOBAL=/dev/null", "GIT_CONFIG_SYSTEM=/dev/null")
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("git %s: %v\n%s", strings.Join(args, " "), err, out)
	}
}

// testEnv builds the env a command would get, capturing both streams so a
// test can assert on data and on diagnostics separately.
func testEnv(root string, w io.Writer) *env {
	return &env{root: root, out: w, errw: w}
}

func mustRun(t *testing.T, root string, args ...string) string {
	t.Helper()
	var out, errw bytes.Buffer
	full := append([]string{args[0], "-C", root}, args[1:]...)
	if err := run(full, &out, &errw); err != nil {
		t.Fatalf("gnopm %s: %v\n%s", strings.Join(args, " "), err, errw.String())
	}
	return out.String() + errw.String()
}

func mustLock(t *testing.T, root string) *Lock {
	t.Helper()
	l, err := readLock(root)
	if err != nil {
		t.Fatal(err)
	}
	return l
}

func write(t *testing.T, p, s string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte(s), 0o644); err != nil {
		t.Fatal(err)
	}
}

func read(t *testing.T, p string) string {
	t.Helper()
	b, err := os.ReadFile(p)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

// --- the migration ----------------------------------------------------------

// TestDeversion is the whole migration on a small tree: two single-version
// packages, one package with two versions, and one nested package. It asserts
// the three properties the real migration is judged on.
func TestDeversion(t *testing.T) {
	root := newRepo(t)
	addPkg(t, root, "p/moul/md/v0", "gno.land/p/moul/md/v0", "package md\n\nfunc A() {}\n")
	addPkg(t, root, "p/moul/md/v1", "gno.land/p/moul/md/v1", "package md\n\nfunc A() {}\nfunc B() {}\n")
	addPkg(t, root, "p/moul/ulist/v0", "gno.land/p/moul/ulist/v0", "package ulist\n")
	addPkg(t, root, "p/moul/ulist/lplist/v0", "gno.land/p/moul/ulist/lplist/v0", "package lplist\n")
	commit(t, root, "seed")

	v0Before := read(t, filepath.Join(root, "p/moul/md/v0/md.gno"))
	v1Before := read(t, filepath.Join(root, "p/moul/md/v1/md.gno"))

	if err := deversion(testEnv(root, &bytes.Buffer{}), false); err != nil {
		t.Fatalf("deversion: %v", err)
	}

	// 1. The highest version wins the unversioned directory, contents intact,
	//    and the module line is NOT rewritten (a realm's address derives from
	//    its package path, so touching it here would move addresses).
	if got := read(t, filepath.Join(root, "p/moul/md/md.gno")); got != v1Before {
		t.Fatalf("md/v1 contents changed in the move:\n got: %q\nwant: %q", got, v1Before)
	}
	mod, _, err := readGnomod(filepath.Join(root, "p/moul/md/gnomod.toml"))
	if err != nil {
		t.Fatal(err)
	}
	if mod != "gno.land/p/moul/md/v1" {
		t.Fatalf("module line is %q, the migration must not touch it", mod)
	}

	// 2. A nested package survives its parent lifting up past it.
	if _, err := os.Stat(filepath.Join(root, "p/moul/ulist/lplist/lplist.gno")); err != nil {
		t.Fatalf("nested package did not migrate: %v", err)
	}
	if got, _, _ := readGnomod(filepath.Join(root, "p/moul/ulist/gnomod.toml")); got != "gno.land/p/moul/ulist/v0" {
		t.Fatalf("parent package module is %q", got)
	}

	// 3. The superseded version left the tree but is still resolvable.
	if _, err := os.Stat(filepath.Join(root, "p/moul/md/v0")); !os.IsNotExist(err) {
		t.Fatal("md/v0 should have left the working tree")
	}
	if err := install(testEnv(root, &bytes.Buffer{})); err != nil {
		t.Fatalf("install: %v", err)
	}
	if got := read(t, filepath.Join(root, ".gnopm/gno.land/p/moul/md/v0/md.gno")); got != v0Before {
		t.Fatalf("md/v0 was not preserved:\n got: %q\nwant: %q", got, v0Before)
	}
	if err := verify(testEnv(root, &bytes.Buffer{})); err != nil {
		t.Fatalf("verify after migration: %v", err)
	}

	// And git records renames, which is the entire point: a reviewer sees
	// "renamed" rather than a pile of added files.
	commit(t, root, "de-version")
	out, err := gitOut(root, "diff", "--name-status", "-M", "HEAD~1", "HEAD")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out, "R100\tp/moul/ulist/v0/ulist.gno\tp/moul/ulist/ulist.gno") {
		t.Fatalf("git did not record the move as a 100%% rename:\n%s", out)
	}
}

func TestDeversionIsIdempotent(t *testing.T) {
	root := newRepo(t)
	addPkg(t, root, "p/moul/md/v0", "gno.land/p/moul/md/v0", "package md\n")
	commit(t, root, "seed")
	if err := deversion(testEnv(root, &bytes.Buffer{}), false); err != nil {
		t.Fatal(err)
	}
	commit(t, root, "de-version")
	var out bytes.Buffer
	if err := deversion(testEnv(root, &out), false); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out.String(), "nothing to do") {
		t.Fatalf("second run was not a no-op: %s", out.String())
	}
}

func TestDeversionRefusesAMismatch(t *testing.T) {
	// A directory that says /v0 while the module says /v1 means somebody
	// copied a package and forgot half the rename. Moving it would silently
	// pick one of the two as the truth.
	root := newRepo(t)
	addPkg(t, root, "p/moul/md/v0", "gno.land/p/moul/md/v1", "package md\n")
	commit(t, root, "seed")
	err := deversion(testEnv(root, &bytes.Buffer{}), true)
	if err == nil || !strings.Contains(err.Error(), "sits in a /v0 directory") {
		t.Fatalf("expected a mismatch refusal, got %v", err)
	}
}

func TestDeversionRefusesUncommittedWork(t *testing.T) {
	root := newRepo(t)
	addPkg(t, root, "p/moul/md/v0", "gno.land/p/moul/md/v0", "package md\n")
	commit(t, root, "seed")
	write(t, filepath.Join(root, "p/moul/md/v0/md.gno"), "package md // wip\n")
	err := deversion(testEnv(root, &bytes.Buffer{}), false)
	if err == nil || !strings.Contains(err.Error(), "uncommitted") {
		t.Fatalf("expected a refusal on uncommitted work, got %v", err)
	}
}

func gitOut(root string, args ...string) (string, error) { return git(root, args...) }

// TestPinSurvivesASquashMerge is the reason choosePin exists.
//
// This repository squash-merges, so a feature branch's commits do not survive
// onto main and are unreachable in a fresh clone once the branch is deleted.
// A version pinned to the branch's HEAD would therefore stop resolving exactly
// when the change lands, and `gnopm verify` would fail on main from then on.
// The pin has to land on a commit that is already upstream.
func TestPinSurvivesASquashMerge(t *testing.T) {
	root := newRepo(t)
	addPkg(t, root, "p/moul/md/v0", "gno.land/p/moul/md/v0", "package md\n\nfunc A() {}\n")
	commit(t, root, "seed")
	mainTip, err := gitHead(root)
	if err != nil {
		t.Fatal(err)
	}

	// A feature branch with a commit that does not touch the package.
	gitCmd(t, root, "checkout", "-q", "-b", "feature")
	write(t, filepath.Join(root, "unrelated.md"), "hello\n")
	commit(t, root, "unrelated work")
	branchTip, err := gitHead(root)
	if err != nil {
		t.Fatal(err)
	}
	if branchTip == mainTip {
		t.Fatal("test setup: the branch did not advance")
	}

	if err := bump(testEnv(root, &bytes.Buffer{}), "p/moul/md/v0", 0, false); err != nil {
		t.Fatal(err)
	}
	l := mustLock(t, root)
	v0, ok, _ := findModule(l, "gno.land/p/moul/md/v0")
	if !ok {
		t.Fatal("v0 was not pinned")
	}
	if v0.Source.Commit == branchTip {
		t.Fatal("pinned to the feature branch's HEAD, which a squash merge discards")
	}
	if v0.Source.Commit != mainTip {
		t.Fatalf("pinned to %s, want main's tip %s", short(v0.Source.Commit), short(mainTip))
	}
}

// TestPinFallsBackAndSaysSo: when the version genuinely exists nowhere but
// this branch, HEAD is the only honest pin, and the user has to be told.
func TestPinFallsBackAndSaysSo(t *testing.T) {
	root := newRepo(t)
	write(t, filepath.Join(root, "seed.md"), "seed\n")
	commit(t, root, "seed")
	gitCmd(t, root, "checkout", "-q", "-b", "feature")
	addPkg(t, root, "p/moul/new/v0", "gno.land/p/moul/new/v0", "package new\n")
	commit(t, root, "add a brand new package")
	branchTip, err := gitHead(root)
	if err != nil {
		t.Fatal(err)
	}

	var out bytes.Buffer
	if err := bump(testEnv(root, &out), "p/moul/new/v0", 0, false); err != nil {
		t.Fatal(err)
	}
	l := mustLock(t, root)
	v0, _, _ := findModule(l, "gno.land/p/moul/new/v0")
	if v0.Source.Commit != branchTip {
		t.Fatalf("pinned to %s, want the branch tip %s", short(v0.Source.Commit), short(branchTip))
	}
	if !strings.Contains(out.String(), "squash-merges") {
		t.Fatalf("the fallback must warn that the pin is not upstream yet:\n%s", out.String())
	}
}

// TestDeversionOnAMixedTree is the situation every open pull request lands in
// after the migration: it rebases onto a migrated main, its own new packages
// still sit at the old pkg/vN paths, and re-running the migration has to fix
// exactly those and leave everything else alone.
func TestDeversionOnAMixedTree(t *testing.T) {
	root := newRepo(t)
	addPkg(t, root, "p/moul/old", "gno.land/p/moul/old/v0", "package old\n")    // already migrated
	addPkg(t, root, "p/moul/new/v0", "gno.land/p/moul/new/v0", "package new\n") // the PR's addition
	commit(t, root, "rebased branch")

	var out bytes.Buffer
	if err := deversion(testEnv(root, &out), false); err != nil {
		t.Fatalf("deversion: %v\n%s", err, out.String())
	}
	if _, err := os.Stat(filepath.Join(root, "p/moul/new/new.gno")); err != nil {
		t.Fatalf("the new package was not de-versioned: %v", err)
	}
	if _, err := os.Stat(filepath.Join(root, "p/moul/old/old.gno")); err != nil {
		t.Fatalf("the already-migrated package was disturbed: %v", err)
	}
	// Nothing was superseded, so nothing should have been pinned to history.
	l := mustLock(t, root)
	if n := len(materializedEntries(l)); n != 0 {
		t.Fatalf("%d entries pinned to history, want 0", n)
	}
	if err := verify(testEnv(root, &bytes.Buffer{})); err != nil {
		t.Fatalf("verify: %v", err)
	}
}

// mustFreeze drives the pinning step directly. It is deliberately not a
// command any more: its only real caller is the migration, and offering both
// `lock` and `freeze` made people ask which one they wanted.
func mustFreeze(t *testing.T, root string) {
	t.Helper()
	pkgs, err := scanPackages(root)
	if err != nil {
		t.Fatal(err)
	}
	old, err := readLock(root)
	if err != nil {
		t.Fatal(err)
	}
	next, err := freezeLock(root, old, pkgs, io.Discard)
	if err != nil {
		t.Fatal(err)
	}
	if err := writeLock(root, next); err != nil {
		t.Fatal(err)
	}
}

// --- CLI surface -------------------------------------------------------------

// TestFlagsGoAnywhere: Go's flag package stops parsing at the first non-flag
// argument, so `gnopm ls md -q` would silently treat -q as another positional
// and print the full table. Insisting on flags-first is exactly the kind of
// thing that makes a CLI annoying, so both orders have to work.
func TestFlagsGoAnywhere(t *testing.T) {
	root := newRepo(t)
	addPkg(t, root, "p/moul/md", "gno.land/p/moul/md/v0", "package md\n")
	addPkg(t, root, "p/moul/other", "gno.land/p/moul/other/v0", "package other\n")
	commit(t, root, "seed")
	mustRun(t, root, "sync")

	for _, args := range [][]string{
		{"ls", "-q", "md"},
		{"ls", "md", "-q"},
	} {
		var out, errw bytes.Buffer
		full := append([]string{args[0], "-C", root}, args[1:]...)
		if err := run(full, &out, &errw); err != nil {
			t.Fatalf("gnopm %s: %v", strings.Join(args, " "), err)
		}
		got := strings.TrimSpace(out.String())
		if got != "gno.land/p/moul/md/v0" {
			t.Errorf("gnopm %s printed %q, want just the matching module path",
				strings.Join(args, " "), got)
		}
	}
}

// TestLsQuietIsPipeable: stdout carries data and nothing else, so a pipe gets
// module paths and not progress lines.
func TestLsQuietIsPipeable(t *testing.T) {
	root := newRepo(t)
	addPkg(t, root, "p/moul/a", "gno.land/p/moul/a/v0", "package a\n")
	addPkg(t, root, "p/moul/b", "gno.land/p/moul/b/v0", "package b\n")
	commit(t, root, "seed")

	var out, errw bytes.Buffer
	// sync writes its progress to stderr, so even when it has something to
	// say it cannot corrupt a pipe.
	if err := run([]string{"sync", "-C", root}, &out, &errw); err != nil {
		t.Fatal(err)
	}
	if out.String() != "" {
		t.Fatalf("sync wrote to stdout: %q", out.String())
	}
	out.Reset()
	if err := run([]string{"ls", "-C", root, "-q"}, &out, &errw); err != nil {
		t.Fatal(err)
	}
	want := "gno.land/p/moul/a/v0\ngno.land/p/moul/b/v0\n"
	if out.String() != want {
		t.Fatalf("ls -q printed %q, want %q", out.String(), want)
	}
}

// TestUnknownCommandSuggests: a typo should cost one line, not a wall of usage.
func TestUnknownCommandSuggests(t *testing.T) {
	root := newRepo(t)
	err := run([]string{"stat", "-C", root}, &bytes.Buffer{}, &bytes.Buffer{})
	if err == nil {
		t.Fatal("unknown command accepted")
	}
	if !strings.Contains(err.Error(), "gnopm status") {
		t.Fatalf("no suggestion in %q", err)
	}
}

// TestCommentsAreNotLoadBearing: the generated header is prose, and prose gets
// edited. If a wording change in it counted as the lock being out of canonical
// form, improving one sentence would invalidate every gnomod.lock in existence
// and fail CI on every repository using the format. verify has to tolerate it,
// and sync has to quietly repair it.
func TestCommentsAreNotLoadBearing(t *testing.T) {
	root := newRepo(t)
	addPkg(t, root, "p/moul/a", "gno.land/p/moul/a/v0", "package a\n")
	commit(t, root, "seed")
	mustRun(t, root, "sync")

	canonical := read(t, filepath.Join(root, lockFile))
	stale := strings.Replace(canonical,
		"# gnomod.lock, generated by gnopm. Do not hand-edit.",
		"# gnomod.lock, written by some older gnopm with different prose.", 1)
	if stale == canonical {
		t.Fatal("test setup: header line not found")
	}
	write(t, filepath.Join(root, lockFile), stale)

	if err := verify(testEnv(root, &bytes.Buffer{})); err != nil {
		t.Fatalf("verify rejected a lock whose only difference is a comment: %v", err)
	}

	var out bytes.Buffer
	if err := cmdSync(testEnv(root, &out)); err != nil {
		t.Fatal(err)
	}
	if got := read(t, filepath.Join(root, lockFile)); got != canonical {
		t.Fatal("sync did not repair the stale header")
	}
	if out.String() != "" {
		t.Fatalf("repairing a comment should be silent, said: %q", out.String())
	}

	// But a real data difference is still caught.
	broken := strings.Replace(canonical, `dir = "p/moul/a"`, `dir = "p/moul/elsewhere"`, 1)
	write(t, filepath.Join(root, lockFile), broken)
	if err := verify(testEnv(root, &bytes.Buffer{})); err == nil {
		t.Fatal("verify accepted a lock pointing at the wrong directory")
	}
}

// TestDeversionLeavesNoEmptyDirectory: git does not track directories, so an
// emptied version directory is invisible to `git status` while `ls` still
// shows it. A package with a subdirectory (filetests/, say) used to leave one
// behind, because a single Remove fails on "directory not empty" and the error
// was ignored.
func TestDeversionLeavesNoEmptyDirectory(t *testing.T) {
	root := newRepo(t)
	addPkg(t, root, "p/moul/authz/v0", "gno.land/p/moul/authz/v0", "package authz\n")
	addPkg(t, root, "p/moul/authz/v1", "gno.land/p/moul/authz/v1", "package authz\n")
	write(t, filepath.Join(root, "p/moul/authz/v1/filetests/z_shape_filetest.gno"), "package main\n")
	write(t, filepath.Join(root, "p/moul/authz/v1/deep/deeper/note.gno"), "package deep\n")
	commit(t, root, "seed")

	if err := deversion(testEnv(root, &bytes.Buffer{}), false); err != nil {
		t.Fatal(err)
	}
	for _, gone := range []string{"p/moul/authz/v0", "p/moul/authz/v1"} {
		if _, err := os.Stat(filepath.Join(root, gone)); !os.IsNotExist(err) {
			t.Errorf("%s still exists after the migration", gone)
		}
	}
	// And the nested files came with it.
	for _, want := range []string{
		"p/moul/authz/filetests/z_shape_filetest.gno",
		"p/moul/authz/deep/deeper/note.gno",
	} {
		if _, err := os.Stat(filepath.Join(root, want)); err != nil {
			t.Errorf("%s did not move: %v", want, err)
		}
	}
}

// TestRemoveEmptyTreeSpareStrayFiles: the prune must never destroy an
// untracked file somebody left behind. Somebody's scratch file is worth more
// than a tidy tree.
func TestRemoveEmptyTreeSparesStrayFiles(t *testing.T) {
	dir := t.TempDir()
	write(t, filepath.Join(dir, "v0", "sub", "scratch.txt"), "do not delete me\n")
	if err := removeEmptyTree(filepath.Join(dir, "v0")); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(dir, "v0", "sub", "scratch.txt")); err != nil {
		t.Fatalf("the stray file was destroyed: %v", err)
	}

	// With nothing but empty directories, it goes.
	empty := filepath.Join(dir, "v1", "a", "b")
	if err := os.MkdirAll(empty, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := removeEmptyTree(filepath.Join(dir, "v1")); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(dir, "v1")); !os.IsNotExist(err) {
		t.Error("an entirely empty tree was not removed")
	}
}
