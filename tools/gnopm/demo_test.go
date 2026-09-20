package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// TestDemoScript runs scripts/demo.sh into a temporary directory.
//
// The script builds a whole repository from nothing and asserts at every step,
// so this is the integration test: it exercises the real binary against real
// git, and it covers the things unit tests structurally cannot, like whether
// git records the migration as renames or whether a version with no directory
// left still materializes byte-for-byte.
//
// It also happens to produce the published demo repository, which is the point
// of writing it this way: a demo that is not executed rots, and a demo that is
// executed as a test cannot.
func TestDemoScript(t *testing.T) {
	if testing.Short() {
		t.Skip("builds a binary and a git repository")
	}
	for _, bin := range []string{"bash", "git", "go"} {
		if _, err := exec.LookPath(bin); err != nil {
			t.Skipf("%s not available", bin)
		}
	}
	script, err := filepath.Abs(filepath.Join("scripts", "demo.sh"))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(script); err != nil {
		t.Fatalf("demo script missing: %v", err)
	}

	// Build the binary once and hand it to the script, so the test exercises
	// this working tree rather than whatever `gnopm` happens to be on PATH.
	bin := filepath.Join(t.TempDir(), "gnopm")
	build := exec.Command("go", "build", "-o", bin, ".")
	if out, err := build.CombinedOutput(); err != nil {
		t.Fatalf("building gnopm: %v\n%s", err, out)
	}

	repo := filepath.Join(t.TempDir(), "gnopm-demo")
	cmd := exec.Command("bash", script, repo)
	cmd.Env = append(os.Environ(),
		"GNOPM="+bin,
		// A hermetic git identity: the script commits, and a machine with no
		// user.name configured would otherwise fail here and nowhere else.
		"GIT_CONFIG_GLOBAL=/dev/null",
		"GIT_CONFIG_SYSTEM=/dev/null",
	)
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("demo.sh failed: %v\n%s", err, out)
	}
	if !strings.Contains(string(out), "all assertions passed") {
		t.Fatalf("demo.sh did not reach the end:\n%s", out)
	}

	// Spot-check the artefact itself, not just the script's own assertions.
	for _, want := range []string{
		"README.md",
		"gnomod.lock",
		"p/demo/strs/gnomod.toml", // de-versioned directory
		".gnopm/gno.land/p/demo/strs/v0/strs.gno",     // superseded, rebuilt from history
		"vendor/gno.land/p/nt/tinyavl/v0/gnomod.toml", // external, untouched
	} {
		if _, err := os.Stat(filepath.Join(repo, want)); err != nil {
			t.Errorf("demo repo is missing %s: %v", want, err)
		}
	}
	if _, err := os.Stat(filepath.Join(repo, "p/demo/strs/v0")); !os.IsNotExist(err) {
		t.Error("p/demo/strs/v0 should have no directory after the migration")
	}
}
