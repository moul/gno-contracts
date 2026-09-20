package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// TestUpstreamIsDetectedNotDemanded: CI used to have to pass
// -upstream origin/main. Every required flag is friction paid forever, and
// this one was avoidable.
func TestUpstreamIsDetectedNotDemanded(t *testing.T) {
	root := newRepo(t)
	addPkg(t, root, "p/moul/a", "gno.land/p/moul/a/v0", "package a\n")
	commit(t, root, "seed")
	// A remote-tracking ref is all the detection needs.
	gitCmd(t, root, "update-ref", "refs/remotes/origin/main", "HEAD")

	if got := upstreamRef(root, ""); got != "origin/main" {
		t.Fatalf("detected %q, want origin/main", got)
	}
	if got := upstreamRef(root, "refs/heads/whatever"); got != "refs/heads/whatever" {
		t.Fatalf("an explicit value must win, got %q", got)
	}
	// A pull request's base branch wins over the default branch.
	gitCmd(t, root, "update-ref", "refs/remotes/origin/release", "HEAD")
	t.Setenv("GITHUB_BASE_REF", "release")
	if got := upstreamRef(root, ""); got != "origin/release" {
		t.Fatalf("GITHUB_BASE_REF ignored, got %q", got)
	}
}

// TestNoRemoteIsNotAnError: a repository with no remote is a legitimate place
// to work, and refusing to operate there would be worse than not checking.
func TestNoRemoteIsNotAnError(t *testing.T) {
	root := newRepo(t)
	addPkg(t, root, "p/moul/a", "gno.land/p/moul/a/v0", "package a\n")
	commit(t, root, "seed")
	if got := upstreamRef(root, ""); got != "" {
		t.Fatalf("invented an upstream out of nothing: %q", got)
	}
	mustRun(t, root, "sync")
	if err := verify(testEnv(root, &bytes.Buffer{})); err != nil {
		t.Fatalf("verify must work without a remote: %v", err)
	}
}

// TestTidyNeedsBothConditions is the whole safety argument for tidy: unused is
// not permission to forget, only unused AND never-shipped is.
func TestTidyNeedsBothConditions(t *testing.T) {
	root := newRepo(t)
	addPkg(t, root, "p/moul/md", "gno.land/p/moul/md/v0", "package md\n")
	commit(t, root, "seed")
	mustRun(t, root, "sync")
	commit(t, root, "lock")
	gitCmd(t, root, "update-ref", "refs/remotes/origin/main", "HEAD")

	// A bump that lands entirely on this branch: v0 never shipped.
	gitCmd(t, root, "checkout", "-q", "-b", "feature")
	if err := bump(testEnv(root, &bytes.Buffer{}), "md", 0, false); err != nil {
		t.Fatal(err)
	}
	commit(t, root, "bump")

	// v0's pin IS upstream here (bump pinned it to origin/main), so tidy must
	// keep it: it shipped.
	var out bytes.Buffer
	if err := tidy(testEnv(root, &out), false); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out.String(), "nothing to tidy") {
		t.Fatalf("tidy dropped a version that shipped: %s", out.String())
	}

	// Now the unshipped case: edit then bump, so the pin is branch-only.
	write(t, filepath.Join(root, "p/moul/md/md.gno"), "package md // v1 body\n")
	commit(t, root, "edit")
	if err := bump(testEnv(root, &bytes.Buffer{}), "md", 0, false); err != nil {
		t.Fatal(err)
	}
	commit(t, root, "bump again")
	out.Reset()
	if err := tidy(testEnv(root, &out), false); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out.String(), "gno.land/p/moul/md/v1") {
		t.Fatalf("tidy kept a version that never shipped and nobody imports: %s", out.String())
	}
	// And the stranded pin is gone, so the upstream guard is satisfied again.
	if err := verifyWith(testEnv(root, &bytes.Buffer{}), "origin/main"); err != nil {
		t.Fatalf("after tidy the upstream check should pass: %v", err)
	}
}

// TestTidyKeepsAnImportedVersion: still imported means still needed, whatever
// its provenance.
func TestTidyKeepsAnImportedVersion(t *testing.T) {
	root := newRepo(t)
	addPkg(t, root, "p/moul/md", "gno.land/p/moul/md/v0", "package md\n")
	addPkg(t, root, "p/moul/user", "gno.land/p/moul/user/v0",
		"package user\n\nimport \"gno.land/p/moul/md/v0\"\n\nfunc U() { _ = md.X }\n")
	commit(t, root, "seed")
	mustRun(t, root, "sync")
	commit(t, root, "lock")
	gitCmd(t, root, "checkout", "-q", "-b", "feature")
	write(t, filepath.Join(root, "p/moul/md/md.gno"), "package md // edited\n")
	commit(t, root, "edit md")
	if err := bump(testEnv(root, &bytes.Buffer{}), "md", 0, false); err != nil {
		t.Fatal(err)
	}
	commit(t, root, "bump md")

	var out bytes.Buffer
	if err := tidy(testEnv(root, &out), false); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out.String(), "nothing to tidy") {
		t.Fatalf("tidy dropped a version that p/moul/user imports: %s", out.String())
	}
}

// TestBumpFindsThePackageYouAreStandingIn.
func TestBumpFindsThePackageYouAreStandingIn(t *testing.T) {
	root := newRepo(t)
	addPkg(t, root, "p/moul/md", "gno.land/p/moul/md/v0", "package md\n")
	write(t, filepath.Join(root, "p/moul/md/filetests/z_x_filetest.gno"), "package main\n")
	commit(t, root, "seed")
	mustRun(t, root, "sync")
	commit(t, root, "lock")

	wd, _ := os.Getwd()
	defer os.Chdir(wd)
	// From a subdirectory of the package, not even the package root.
	if err := os.Chdir(filepath.Join(root, "p/moul/md/filetests")); err != nil {
		t.Fatal(err)
	}
	got, err := packageAtCwd(root)
	if err != nil {
		t.Fatal(err)
	}
	if got != "p/moul/md" {
		t.Fatalf("found %q, want p/moul/md", got)
	}
	if err := os.Chdir(root); err != nil {
		t.Fatal(err)
	}
	if _, err := packageAtCwd(root); err == nil {
		t.Fatal("the workspace root is not a package; it must say so")
	}
}
