package main

import (
	"os/exec"
	"reflect"
	"strings"
	"testing"
)

func TestClassifyPath(t *testing.T) {
	cases := map[string]string{
		"p/moul/md/v0/md.gno":      "p",
		"r/moul/home/v0/home.gno":  "r",
		".github/workflows/ci.yml": "meta",
		"tools/gnocontracts/pr.go": "meta",
		"Makefile":                 "meta",
		"AGENTS.md":                "meta",
		".gitignore":               "meta",
		"scratch/notes.txt":        "other",
		// Neutral: a consequence of a change, never its intent.
		"vendor/gno.land/p/nt/avl/avl.gno": "",
		"_assets/graph.svg":                "",
		"contracts.json":                   "",
		"gnomod.lock":                      "",
	}
	for path, want := range cases {
		got := classifyPath(path, nil)
		if want == "" {
			if len(got) != 0 {
				t.Errorf("classifyPath(%q) = %v, want no label", path, got)
			}
			continue
		}
		if !reflect.DeepEqual(got, []string{want}) {
			t.Errorf("classifyPath(%q) = %v, want [%s]", path, got, want)
		}
	}
}

func TestClassifyPathDedupes(t *testing.T) {
	var labels []string
	for _, p := range []string{"p/a/x.gno", "p/b/y.gno", "r/c/z.gno"} {
		labels = classifyPath(p, labels)
	}
	if !reflect.DeepEqual(labels, []string{"p", "r"}) {
		t.Fatalf("labels = %v, want [p r]", labels)
	}
}

// Every managed label is always passed to `gh pr edit`, as an add or a remove:
// that is what makes the bot converge when a push stops touching r/.
func TestLabelArgsReconcilesTheWholeManagedSet(t *testing.T) {
	got := labelArgs([]string{"p", "meta"})
	want := []string{"--add-label", "p", "--remove-label", "r", "--add-label", "meta", "--remove-label", "other"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("labelArgs = %v\nwant %v", got, want)
	}
	if n := len(labelArgs(nil)); n != 2*len(managedLabels) {
		t.Fatalf("labelArgs(nil) has %d args, want %d", n, 2*len(managedLabels))
	}
}

func TestThousands(t *testing.T) {
	for in, want := range map[int]string{0: "0", 999: "999", 1000: "1000", 5212: "5212", 12345: "12,345", 1234567: "1,234,567"} {
		if got := thousands(in); got != want {
			t.Errorf("thousands(%d) = %s, want %s", in, got, want)
		}
	}
}

func TestPreviewSelectorSkipsPureAndArchivedPackages(t *testing.T) {
	root := fixture(t, map[string]string{
		"r/moul/live/v0/r.gno":      "package live\n",
		"r/moul/old/v0/gnomod.toml": "module = \"gno.land/r/moul/old/v0\"\nignore = true\n",
		"r/moul/old/v0/r.gno":       "package old\n",
		"p/moul/lib/v0/l.gno":       "package lib\n",
	})
	if sel, ok := previewSelector(root, "r/moul/live/v0"); !ok || sel != "./r/moul/live/v0" {
		t.Fatalf("live realm: got (%q, %v)", sel, ok)
	}
	if _, ok := previewSelector(root, "r/moul/old/v0"); ok {
		t.Fatal("archived realm selected for preview")
	}
	if _, ok := previewSelector(root, "p/moul/lib/v0"); ok {
		t.Fatal("pure package selected for preview")
	}
}

// git builds a real repository, because the PR analysis is a diff and mocking
// git would only test the mock.
func gitRepo(t *testing.T, root string) {
	t.Helper()
	for _, args := range [][]string{
		{"init", "-q", "-b", "main"},
		{"config", "user.email", "t@example.org"},
		{"config", "user.name", "t"},
		{"add", "-A"},
		{"commit", "-qm", "base"},
	} {
		cmd := exec.Command("git", append([]string{"-C", root}, args...)...)
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
	}
}

func TestPRCommentStaysShortWhateverTheDiffSize(t *testing.T) {
	root := fixture(t, map[string]string{"README.md": "# base\n"})
	gitRepo(t, root)

	// 12 new realms, each with a Render and a pinned example: the shape of the
	// pull request that used to render 45 lines.
	files := map[string]string{}
	for _, n := range []string{"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l"} {
		files["r/moul/x/"+n+"/v0/r.gno"] = "package " + n + "\n\nfunc Render(p string) string { return \"\" }\n"
		files["r/moul/x/"+n+"/v0/r_test.gno"] = "package " + n + "\n\nfunc ExampleRender() {\n\t// Output:\n}\n"
	}
	// One of them handles coins and has no README of its own.
	files["r/moul/x/a/v0/r.gno"] = "package a\n\nimport \"chain/banker\"\n\nfunc Render(p string) string { return \"\" }\n"
	for rel, body := range files {
		writeFileAt(t, root, rel, body)
	}
	gitCommit(t, root, "add realms")

	a, err := analyzePR(root, "HEAD~1")
	if err != nil {
		t.Fatal(err)
	}
	if len(a.newPkgs) != 12 {
		t.Fatalf("new packages = %d, want 12", len(a.newPkgs))
	}
	if len(a.selectors) != 12 {
		t.Fatalf("preview selectors = %d, want 12", len(a.selectors))
	}
	if !reflect.DeepEqual(a.labels, []string{"r"}) {
		t.Fatalf("labels = %v, want [r]", a.labels)
	}

	body := renderPRComment(root, a, "HEAD~1", "https://example.org/pr-1/", "", "")

	// Visible size is what this is about: everything below a <details> is folded.
	visible := 0
	for _, ln := range strings.Split(body, "\n") {
		if strings.HasPrefix(ln, "<details>") {
			break
		}
		if strings.TrimSpace(ln) != "" && !strings.HasPrefix(ln, "<!--") {
			visible++
		}
	}
	if visible > 4 {
		t.Fatalf("comment shows %d lines before folding, want at most 4:\n%s", visible, body)
	}
	if !strings.HasPrefix(body, prMarker) {
		t.Fatal("comment does not start with the sticky marker")
	}
	for _, want := range []string{"**12 new**", "🔥 1 coins", "📝 12 no README", "https://example.org/pr-1/", "<details>"} {
		if !strings.Contains(body, want) {
			t.Fatalf("comment missing %q:\n%s", want, body)
		}
	}
	// The per-package detail is still there, just folded.
	if n := strings.Count(body, "| 🆕 "); n != 12 {
		t.Fatalf("folded table has %d rows, want 12", n)
	}
}

func TestPRCommentOnAnEmptyDiff(t *testing.T) {
	root := fixture(t, map[string]string{"README.md": "# base\n"})
	gitRepo(t, root)
	writeFileAt(t, root, "README.md", "# base\n\nprose\n")
	gitCommit(t, root, "prose")

	a, err := analyzePR(root, "HEAD~1")
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(a.labels, []string{"meta"}) {
		t.Fatalf("labels = %v, want [meta]", a.labels)
	}
	body := renderPRComment(root, a, "HEAD~1", "https://example.org/pr-1/", "", "")
	if strings.Contains(body, "<details>") {
		t.Fatalf("no packages changed, yet the comment folds a table:\n%s", body)
	}
	if strings.Contains(body, "Preview") {
		t.Fatalf("no realms changed, yet the comment offers a preview:\n%s", body)
	}
}
