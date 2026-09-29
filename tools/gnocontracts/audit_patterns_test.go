package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// auditFixture builds a workspace of packages plus the catalog contractDirs
// reads. Each entry is "<dir>": "<one .gno file's body>"; the gnomod.toml and
// the manifest row are derived.
func auditFixture(t *testing.T, srcs map[string]string) string {
	t.Helper()
	root := t.TempDir()
	writeFile(t, root, "gnowork.toml", "")
	m := Manifest{Networks: defaultNetworks()}
	for dir, body := range srcs {
		full := filepath.Join(root, filepath.FromSlash(dir))
		if err := os.MkdirAll(full, 0o755); err != nil {
			t.Fatal(err)
		}
		path := "gno.land/" + dir + "/v0"
		writeFile(t, full, "gnomod.toml", mod(path))
		writeFile(t, full, "x.gno", body)
		m.Contracts = append(m.Contracts, Contract{PkgPath: path, Dir: dir})
	}
	b, err := json.Marshal(m)
	if err != nil {
		t.Fatal(err)
	}
	writeFile(t, root, manifestFile, string(b))
	return root
}

// leakySrc exports a pointer to a mutable /p/ type, which is two rules at once:
// exported_pointer_leak and pkg_mutable_pointer.
const leakySrc = "package x\n\nvar t *avl.Tree\n\nfunc Tree() *avl.Tree { return t }\n"

const cleanSrc = "package x\n\nfunc Add(a, b int) int { return a + b }\n"

func TestAuditPatternsPassesWhenTheBaselineMatches(t *testing.T) {
	root := auditFixture(t, map[string]string{"r/moul/leaky": leakySrc})
	mustAudit(t, root, "-update")
	mustAudit(t, root) // no flags: the gate
}

func TestAuditPatternsFailsOnAHitTheBaselineDoesNotRecord(t *testing.T) {
	root := auditFixture(t, map[string]string{"r/moul/leaky": leakySrc})
	if err := cmdAuditPatterns(root, nil); err == nil {
		t.Fatal("want a failure with no baseline at all, got nil")
	} else if !strings.Contains(err.Error(), "new audit-pattern hits") {
		t.Fatalf("want the new-hits failure, got %v", err)
	}
}

func TestAuditPatternsFailsWhenTheBaselineIsTooGenerous(t *testing.T) {
	root := auditFixture(t, map[string]string{"r/moul/leaky": leakySrc})
	mustAudit(t, root, "-update")

	// The fix lands; the baseline still claims the debt.
	writeFile(t, filepath.Join(root, "r", "moul", "leaky"), "x.gno", cleanSrc)

	err := cmdAuditPatterns(root, nil)
	if err == nil {
		t.Fatal("want a failure when the tree improved and the baseline did not, got nil")
	}
	if !strings.Contains(err.Error(), "too generous") {
		t.Fatalf("want the too-generous failure, got %v", err)
	}
}

// The realm-only rules are upstream's own framing, and the cost of getting this
// wrong is 96 extra rows of iterator callbacks burying the realm hits.
func TestAuditPatternsSkipsRealmOnlyRulesInPurePackages(t *testing.T) {
	root := auditFixture(t, map[string]string{
		"p/moul/leaky": leakySrc,
		"r/moul/leaky": leakySrc,
	})
	mustAudit(t, root, "-update")

	b, err := os.ReadFile(filepath.Join(root, auditBaselineFile))
	if err != nil {
		t.Fatal(err)
	}
	got := string(b)
	if !strings.Contains(got, "exported_pointer_leak r/moul/leaky") {
		t.Fatalf("the realm's leak should be recorded, baseline is:\n%s", got)
	}
	if strings.Contains(got, "exported_pointer_leak p/moul/leaky") {
		t.Fatalf("a p/ constructor returning a pointer is not this finding, baseline is:\n%s", got)
	}
}

func TestAuditPatternsRejectsAnUnknownRule(t *testing.T) {
	root := auditFixture(t, map[string]string{"r/moul/leaky": cleanSrc})
	if err := cmdAuditPatterns(root, []string{"-rule", "no_such_rule"}); err == nil {
		t.Fatal("want an error for an unknown rule, got nil")
	}
}

// A malformed baseline must say which line, not fail somewhere downstream.
func TestAuditPatternsRejectsAMalformedBaseline(t *testing.T) {
	root := auditFixture(t, map[string]string{"r/moul/leaky": cleanSrc})
	dir := filepath.Join(root, "tools", "gnocontracts")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	writeFile(t, dir, "audit-pattern-baseline.txt", "current_guard r/moul/leaky\n")
	err := cmdAuditPatterns(root, nil)
	if err == nil || !strings.Contains(err.Error(), "want `rule dir count`") {
		t.Fatalf("want the malformed-line error naming the shape, got %v", err)
	}
}

func mustAudit(t *testing.T, root string, args ...string) {
	t.Helper()
	if err := cmdAuditPatterns(root, args); err != nil {
		t.Fatalf("audit-patterns %v: %v", args, err)
	}
}
