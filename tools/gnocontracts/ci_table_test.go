package main

import (
	"os"
	"path/filepath"
	"regexp"
	"sort"
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
	files := workflowFiles(t, root)
	for name := range ciTableRows(t, root) {
		if _, ok := files[name]; !ok {
			t.Errorf("AGENTS.md's CI table has a row for %q, but neither .github/workflows/%s.yml nor .yaml exists", name, name)
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

// workflowFiles maps each workflow name to its file under .github/workflows/.
// GitHub runs both extensions, so a gate added as .yaml is as real as a .yml
// one and has to be found by the same scan.
func workflowFiles(t *testing.T, root string) map[string]string {
	t.Helper()
	dir := filepath.Join(root, ".github", "workflows")
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	out := map[string]string{}
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		ext := filepath.Ext(e.Name())
		if ext != ".yml" && ext != ".yaml" {
			continue
		}
		out[strings.TrimSuffix(e.Name(), ext)] = filepath.Join(dir, e.Name())
	}
	return out
}

// pullRequestWorkflows returns every workflow under .github/workflows/ that
// triggers on a pull request, sorted so failures read the same on every run.
func pullRequestWorkflows(t *testing.T, root string) []string {
	t.Helper()
	var out []string
	for name, path := range workflowFiles(t, root) {
		b, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		if triggersOnPullRequest(string(b)) {
			out = append(out, name)
		}
	}
	if len(out) == 0 {
		t.Fatal("no workflow triggers on pull_request; the on: block parser has stopped working")
	}
	sort.Strings(out)
	return out
}

// prEventRe matches the two events that run a workflow on a pull request as
// whole words, so `pull_request_review` and a branch named `pull_requests`
// do not count.
var prEventRe = regexp.MustCompile(`(^|[^A-Za-z0-9_])(pull_request|pull_request_target)([^A-Za-z0-9_]|$)`)

// onKeyRe matches the top-level trigger key in its plain and quoted
// spellings, capturing whatever follows the colon on the same line.
var onKeyRe = regexp.MustCompile(`^(on|"on"|'on'):(.*)$`)

// triggersOnPullRequest reports whether a workflow's `on:` declares a
// pull_request or pull_request_target trigger, in any of the forms GitHub
// accepts: a scalar (`on: pull_request`), a flow sequence or mapping on the
// same line (`on: [push, pull_request]`), a block sequence (`- pull_request`)
// or a block mapping (`pull_request:`). It is read by indentation rather than
// with a YAML parser, which the tools module does not have. In the block
// forms only the first indentation level under `on:` is an event name, so a
// `types:` or `branches:` list nested under an event never counts.
func triggersOnPullRequest(workflow string) bool {
	inOn := false
	indent := -1
	for _, line := range strings.Split(workflow, "\n") {
		if i := strings.Index(line, "#"); i >= 0 {
			line = line[:i]
		}
		if !inOn {
			m := onKeyRe.FindStringSubmatch(strings.TrimRight(line, " \t\r"))
			if m == nil {
				continue
			}
			if rest := strings.TrimSpace(m[2]); rest != "" {
				return prEventRe.MatchString(rest)
			}
			inOn = true
			continue
		}
		trimmed := strings.TrimSpace(line)
		if trimmed == "" {
			continue
		}
		lead := len(line) - len(strings.TrimLeft(line, " \t"))
		if lead == 0 {
			return false // the next top-level key: the on: block is over
		}
		if indent < 0 {
			indent = lead
		}
		if lead != indent {
			continue
		}
		event := strings.TrimSpace(strings.TrimPrefix(trimmed, "-"))
		if i := strings.Index(event, ":"); i >= 0 {
			event = event[:i]
		}
		event = strings.Trim(strings.TrimSpace(event), `"'`)
		if event == "pull_request" || event == "pull_request_target" {
			return true
		}
	}
	return false
}

func TestTriggersOnPullRequest(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want bool
	}{
		{"block mapping", "on:\n  push:\n  pull_request:\n    types: [opened]\njobs:\n", true},
		{"block mapping, empty value", "on:\n  pull_request:\n", true},
		{"block mapping with null", "on:\n  pull_request: ~\n", true},
		{"pull_request_target", "on:\n  pull_request_target:\n", true},
		{"scalar", "on: pull_request\njobs:\n", true},
		{"flow sequence", "on: [push, pull_request]\n", true},
		{"flow mapping", "on: {pull_request: {branches: [main]}}\n", true},
		{"block sequence", "on:\n  - push\n  - pull_request\n", true},
		{"quoted key", "\"on\":\n  pull_request:\n", true},
		{"quoted event", "on:\n  'pull_request':\n", true},
		{"comment after on", "on: # triggers\n  pull_request:\n", true},
		{"crlf", "on:\r\n  pull_request:\r\n", true},
		{"push only", "on:\n  push:\n    branches: [main]\n", false},
		{"schedule only", "on:\n  schedule:\n    - cron: \"17 * * * *\"\n", false},
		{"nested, not an event", "on:\n  push:\n    branches:\n      - pull_request\n", false},
		{"review is another event", "on: [pull_request_review]\n", false},
		{"after the on block", "on:\n  push:\njobs:\n  pull_request:\n", false},
		{"commented out", "on:\n  push:\n  # pull_request:\n", false},
		{"no on at all", "jobs:\n  build:\n", false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := triggersOnPullRequest(tc.in); got != tc.want {
				t.Errorf("triggersOnPullRequest(%q) = %v, want %v", tc.in, got, tc.want)
			}
		})
	}
}
