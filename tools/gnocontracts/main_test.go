package main

import (
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// A printed usage line is a claimed command. This one used to read
// `go run ./tools <command> [flags]`, which exits 1 from the repository root (a
// gno repository root has no go.mod, and the tools are their own module at
// tools/go.mod) and exits 1 from tools/ (there is no tools/tools). AGENTS.md
// routes an agent to this help twice as the place the repository explains how
// to call its own CLI, so the one discovery command handed back a command that
// cannot run.
//
// The Makefile's GNOCONTRACTS variable is the owner of the invocation form, and
// all seven workflows use it. This holds the usage line to that owner instead of
// letting a second copy of the string drift away from it.
func TestUsageInvocationMatchesMakefile(t *testing.T) {
	root, err := repoRoot()
	if err != nil {
		t.Skipf("not inside the repo: %v", err)
	}
	b, err := os.ReadFile(filepath.Join(root, "Makefile"))
	if err != nil {
		t.Fatal(err)
	}
	m := regexp.MustCompile(`(?m)^GNOCONTRACTS\s*\?=\s*(.+?)\s*$`).FindSubmatch(b)
	if m == nil {
		t.Fatal("Makefile declares no GNOCONTRACTS variable: this test is guarding the wrong file")
	}
	want := string(m[1])

	if invocation != want {
		t.Errorf("invocation const = %q, Makefile GNOCONTRACTS = %q", invocation, want)
	}
	// And the help has to actually print it, not merely declare it.
	out := captureUsage(t)
	if line := "usage: " + want + " <command> [flags]"; !strings.Contains(out, line) {
		t.Errorf("usage() does not print %q; got:\n%s", line, out[:min(len(out), 200)])
	}
}

// The package doc carries the same command, and a doc comment is the other
// thing a reader of this file takes as instruction.
func TestPackageDocNamesTheRealInvocation(t *testing.T) {
	b, err := os.ReadFile("main.go")
	if err != nil {
		t.Fatal(err)
	}
	doc, _, ok := strings.Cut(string(b), "\npackage main")
	if !ok {
		t.Fatal("main.go has no package clause")
	}
	if strings.Contains(doc, "go run ./tools") {
		t.Errorf("the package doc still names `go run ./tools`, which exits 1; use %q", invocation)
	}
}

func captureUsage(t *testing.T) string {
	t.Helper()
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	saved := os.Stderr
	os.Stderr = w
	usage()
	os.Stderr = saved
	w.Close()
	out, err := io.ReadAll(r)
	r.Close()
	if err != nil {
		t.Fatal(err)
	}
	return string(out)
}
