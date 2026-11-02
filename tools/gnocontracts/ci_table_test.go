package main

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// AGENTS.md § CI carries a table headed "what it owns", and a table that
// enumerates a set is a claim that the set is complete. It was not: for four
// audit passes it listed three of the seven workflows, and the two it omitted
// that matter are audit-patterns (a pass/fail ratchet on every pull request,
// deliberately outside `make guards`) and gnobench. A contributor who read the
// table, ran the commands it names and saw green could still be blocked by a
// gate the document never mentioned.
//
// Prose cannot hold that. This does: the workflow directory is the owner of
// which gates exist, and the table has to keep up with it. Scoped to the
// workflows that trigger on pull_request, because those are the ones that can
// block a merge, which is the part a reader needs.
func TestCITableNamesEveryPullRequestWorkflow(t *testing.T) {
	root, err := repoRoot()
	if err != nil {
		t.Skipf("not inside the repo: %v", err)
	}
	rows := ciTableRows(t, root)
	if len(rows) == 0 {
		t.Fatal("AGENTS.md § CI: no table rows found; has the table moved or lost its header?")
	}
	for _, name := range pullRequestWorkflows(t, root) {
		if !rows[name] {
			t.Errorf("workflow %q triggers on pull_request and has no row in AGENTS.md's CI table; a gate a contributor cannot find is a gate they discover by being blocked", name)
		}
	}
}

// The other direction: a row for a workflow that no longer exists sends a
// reader looking for a file that is not there.
func TestCITableNamesNoWorkflowThatIsGone(t *testing.T) {
	root, err := repoRoot()
	if err != nil {
		t.Skipf("not inside the repo: %v", err)
	}
	for name := range ciTableRows(t, root) {
		p := filepath.Join(root, ".github", "workflows", name+".yml")
		if _, err := os.Stat(p); err != nil {
			t.Errorf("AGENTS.md's CI table has a row for %q, but %s does not exist", name, filepath.Join(".github", "workflows", name+".yml"))
		}
	}
}

var ciRowRe = regexp.MustCompile("^\\|\\s*`([a-z0-9-]+)`\\s*\\|")

// ciTableRows returns the workflow name in the first cell of every row of the
// table under the "| workflow | when | what it owns |" header in AGENTS.md.
func ciTableRows(t *testing.T, root string) map[string]bool {
	t.Helper()
	b, err := os.ReadFile(filepath.Join(root, "AGENTS.md"))
	if err != nil {
		t.Fatal(err)
	}
	rows := map[string]bool{}
	inTable := false
	for _, line := range strings.Split(string(b), "\n") {
		if strings.HasPrefix(line, "| workflow | when | what it owns |") {
			inTable = true
			continue
		}
		if !inTable {
			continue
		}
		if !strings.HasPrefix(line, "|") {
			break
		}
		if m := ciRowRe.FindStringSubmatch(line); m != nil {
			rows[m[1]] = true
		}
	}
	return rows
}

// pullRequestWorkflows returns every workflow under .github/workflows/ whose
// `on:` block declares a pull_request trigger. The block is read by
// indentation rather than with a YAML parser, which the tools module does not
// have: `on:` at column 0, its keys indented under it, and the block ends at
// the next unindented line.
func pullRequestWorkflows(t *testing.T, root string) []string {
	t.Helper()
	dir := filepath.Join(root, ".github", "workflows")
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	var out []string
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".yml") {
			continue
		}
		b, err := os.ReadFile(filepath.Join(dir, e.Name()))
		if err != nil {
			t.Fatal(err)
		}
		inOn := false
		for _, line := range strings.Split(string(b), "\n") {
			if line == "on:" || strings.HasPrefix(line, "on: ") {
				inOn = true
				continue
			}
			if !inOn {
				continue
			}
			if line != "" && !strings.HasPrefix(line, " ") && !strings.HasPrefix(line, "\t") {
				break
			}
			if trimmed := strings.TrimSpace(line); trimmed == "pull_request:" || strings.HasPrefix(trimmed, "pull_request:") {
				out = append(out, strings.TrimSuffix(e.Name(), ".yml"))
				break
			}
		}
	}
	if len(out) == 0 {
		t.Fatal("no workflow triggers on pull_request; the on: block parser has stopped working")
	}
	return out
}
