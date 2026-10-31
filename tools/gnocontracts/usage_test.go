package main

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// The help banner's `usage:` line is the one thing in this repository whose
// whole job is to be pasted, and it was wrong: it read `go run ./tools
// <command>`, which exits 1 from the repository root (no go.mod there) and
// exits 1 from tools/ (no ./tools there). Every other copy of the invocation
// (the Makefile's GNOCONTRACTS, AGENTS.md) already said `go -C tools tool
// gnocontracts`, so the banner was the single stale one, and it was the copy a
// reader reaches by running the tool rather than by reading a file.
//
// The Makefile is the owner: it is what CI and every target actually run. This
// pins the banner to it rather than to a literal, so moving the tool moves one
// string and the gate follows.
func TestUsageInvocationMatchesMakefile(t *testing.T) {
	root, err := repoRoot()
	if err != nil {
		t.Skipf("not inside the repo: %v", err)
	}
	mk, err := os.ReadFile(filepath.Join(root, "Makefile"))
	if err != nil {
		t.Fatal(err)
	}
	mkRe := regexp.MustCompile(`(?m)^GNOCONTRACTS\s*\?=\s*(.+?)\s*$`)
	m := mkRe.FindSubmatch(mk)
	if m == nil {
		t.Fatal("no `GNOCONTRACTS ?= ...` line in the Makefile; if it moved, this test has to follow it")
	}
	want := string(m[1])

	usageRe := regexp.MustCompile(`(?m)^usage:\s*(.+?)\s+<command>`)
	u := usageRe.FindStringSubmatch(usageText)
	if u == nil {
		t.Fatal("no `usage: <command> ...` line in usageText")
	}
	if got := u[1]; got != want {
		t.Errorf("usage banner names %q, Makefile runs %q: a reader pasting the banner gets a command that does not exist", got, want)
	}
}

// Every command the banner lists has to be one main() dispatches on, or the
// banner sends a reader to a command that errors out. The reverse is not
// checked: an undocumented command is a gap, not a lie.
func TestUsageListsOnlyRealCommands(t *testing.T) {
	root, err := repoRoot()
	if err != nil {
		t.Skipf("not inside the repo: %v", err)
	}
	src, err := os.ReadFile(filepath.Join(root, "tools", "gnocontracts", "main.go"))
	if err != nil {
		t.Fatal(err)
	}
	caseRe := regexp.MustCompile(`(?m)^\tcase\s+(.+?):\s*$`)
	known := map[string]bool{}
	for _, c := range caseRe.FindAllStringSubmatch(string(src), -1) {
		for _, lit := range strings.Split(c[1], ",") {
			if s := strings.Trim(strings.TrimSpace(lit), `"`); s != "" {
				known[s] = true
			}
		}
	}
	if len(known) == 0 {
		t.Fatal("no `case \"...\":` dispatch found in main.go; if the dispatch moved, this test has to follow it")
	}

	_, body, ok := strings.Cut(usageText, "commands:\n")
	if !ok {
		t.Fatal("no `commands:` block in usageText")
	}
	cmdRe := regexp.MustCompile(`^  (\S+)\s`)
	listed := 0
	for _, line := range strings.Split(body, "\n") {
		m := cmdRe.FindStringSubmatch(line)
		if m == nil {
			continue // a continuation line of the previous command's description
		}
		listed++
		if !known[m[1]] {
			t.Errorf("the banner lists %q, which main() does not dispatch on", m[1])
		}
	}
	if listed == 0 {
		t.Fatal("the banner's commands block parsed to zero commands")
	}
}
