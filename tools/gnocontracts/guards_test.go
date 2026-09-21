package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// fixture builds a throwaway workspace: gnowork.toml at the root, then
// "<dir>/<file>": "<content>" for everything else. A gnomod.toml is written for
// any package directory that does not declare its own.
func fixture(t *testing.T, files map[string]string) string {
	t.Helper()
	root := t.TempDir()
	writeFile(t, root, "gnowork.toml", "")
	pkgs := map[string]bool{}
	for rel, body := range files {
		full := filepath.Join(root, filepath.FromSlash(rel))
		if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(full, []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
		if strings.HasSuffix(rel, ".gno") {
			pkgs[filepath.ToSlash(filepath.Dir(rel))] = true
		}
	}
	for dir := range pkgs {
		gm := filepath.Join(root, filepath.FromSlash(dir), "gnomod.toml")
		if fileExists(gm) {
			continue
		}
		if err := os.WriteFile(gm, []byte("module = \"gno.land/"+dir+"\"\ngno = \"0.9\"\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return root
}

func TestGuardExamplesRequiresAnOutputBlock(t *testing.T) {
	root := fixture(t, map[string]string{
		"p/moul/ok/v0/x.gno":      "package ok\n\nfunc H() string { return \"hi\" }\n",
		"p/moul/ok/v0/x_test.gno": "package ok\n\nfunc ExampleH() {\n\tprint(H())\n\t// Output:\n\t// hi\n}\n",
	})
	if err := cmdGuardExamples(root); err != nil {
		t.Fatalf("pinned example rejected: %v", err)
	}

	root = fixture(t, map[string]string{
		"p/moul/bad/v0/x.gno":      "package bad\n\nfunc H() string { return \"hi\" }\n",
		"p/moul/bad/v0/x_test.gno": "package bad\n\nfunc ExampleH() {\n\tprint(H())\n}\n",
	})
	if err := cmdGuardExamples(root); err == nil {
		t.Fatal("example with no // Output: accepted")
	}
}

// The regexp version of this guard read `// Output:` out of a STRING literal
// and called the example pinned. A test that asserts nothing then shipped
// green, which is the exact failure the guard exists to prevent.
func TestGuardExamplesIgnoresOutputInsideAStringLiteral(t *testing.T) {
	root := fixture(t, map[string]string{
		"p/moul/s/v0/x.gno":      "package s\n\nfunc H() string { return \"hi\" }\n",
		"p/moul/s/v0/x_test.gno": "package s\n\nfunc ExampleH() {\n\ts := \"// Output:\\n// hi\"\n\t_ = s\n}\n",
	})
	if err := cmdGuardExamples(root); err == nil {
		t.Fatal("`// Output:` inside a string literal counted as an output block")
	}
}

func TestGuardExamplesAcceptsUnorderedOutput(t *testing.T) {
	root := fixture(t, map[string]string{
		"p/moul/u/v0/x.gno":      "package u\n\nfunc H() string { return \"hi\" }\n",
		"p/moul/u/v0/x_test.gno": "package u\n\nfunc ExampleH() {\n\tprint(H())\n\t// Unordered output:\n\t// hi\n}\n",
	})
	if err := cmdGuardExamples(root); err != nil {
		t.Fatalf("unordered output rejected: %v", err)
	}
}

func TestGuardRenderAcceptsACallFromAnyTestKind(t *testing.T) {
	for _, testFile := range []string{"r_test.gno", "z_filetest.gno"} {
		root := fixture(t, map[string]string{
			"r/moul/a/v0/r.gno":       "package a\n\nfunc Render(path string) string { return \"hi\" }\n",
			"r/moul/a/v0/" + testFile: "package a\n\nfunc ExampleRender() {\n\tprint(a.Render(\"\"))\n\t// Output:\n\t// hi\n}\n",
		})
		if err := cmdGuardRender(root); err != nil {
			t.Fatalf("%s: qualified call not counted: %v", testFile, err)
		}
	}
}

func TestGuardRenderRejectsAnUnexercisedRender(t *testing.T) {
	root := fixture(t, map[string]string{
		"r/moul/a/v0/r.gno": "package a\n\nfunc Render(path string) string { return \"hi\" }\n",
	})
	err := cmdGuardRender(root)
	if err == nil || !strings.Contains(err.Error(), "r/moul/a/v0") {
		t.Fatalf("unexercised Render accepted: %v", err)
	}
}

// Two decoys the regexp version fell for: `Render(` written inside a string
// literal, and an identifier that merely ends in Render.
func TestGuardRenderIgnoresStringsCommentsAndLongerIdentifiers(t *testing.T) {
	root := fixture(t, map[string]string{
		"r/moul/c/v0/r.gno": "package c\n\nfunc Render(path string) string { return \"hi\" }\n\nfunc printRender() {}\n",
		"r/moul/c/v0/r_test.gno": "package c\n\nfunc TestX(t *testing.T) {\n" +
			"\tprintRender()\n" +
			"\t// see https://example.org/Render(1)\n" +
			"\ts := \"call Render(x) later\"\n\t_ = s\n}\n",
	})
	if err := cmdGuardRender(root); err == nil {
		t.Fatal("a Render( inside a string or a comment counted as a call")
	}
}

// A method named Render is not a realm entry point.
func TestGuardRenderIgnoresMethodsAndCommentedDeclarations(t *testing.T) {
	root := fixture(t, map[string]string{
		"r/moul/m/v0/r.gno": "package m\n\ntype T struct{}\n\nfunc (t T) Render(path string) string { return \"\" }\n" +
			"\n// func Render(path string) string { return \"\" }\n",
	})
	if err := cmdGuardRender(root); err != nil {
		t.Fatalf("method / commented-out Render treated as a declaration: %v", err)
	}
}

func TestGuardRenderSkipsArchivedPackages(t *testing.T) {
	root := fixture(t, map[string]string{
		"r/moul/old/v0/gnomod.toml": "module = \"gno.land/r/moul/old/v0\"\ngno = \"0.9\"\nignore = true\n",
		"r/moul/old/v0/r.gno":       "package old\n\nfunc Render(path string) string { return \"hi\" }\n",
	})
	if err := cmdGuardRender(root); err != nil {
		t.Fatalf("archived package not skipped: %v", err)
	}
}

// The guard's whole point: a MISSING README passes, a placeholder does not.
func TestGuardReadmesAllowsMissingAndRejectsPlaceholders(t *testing.T) {
	footer := "\n" + pkgFooterBegin + "\nrepo link, graph, disclaimer\n" + pkgFooterEnd + "\n"
	for _, tt := range []struct {
		name   string
		readme string // "" means no README file at all
		ok     bool
	}{
		{"missing", "", true},
		{"real body", "# `gno.land/p/moul/x`\n\nBuild Markdown tables." + footer, true},
		{"todo stub", "# `gno.land/p/moul/x`\n\n_TODO: describe this package._" + footer, false},
		{"title only", "# `gno.land/p/moul/x`\n" + footer, false},
		{"too short", "# `gno.land/p/moul/x`\n\nA thing." + footer, false},
		{"wip bullet", "# `gno.land/p/moul/x`\n\n- WIP, come back later, it will be great\n" + footer, false},
		// The placeholder words are only rejected as the START of a line: a
		// README saying the package has an unimplemented TODO is describing it.
		{"todo mid-sentence", "# `gno.land/p/moul/x`\n\nProposals are a TODO: every path panics.\n" + footer, true},
	} {
		t.Run(tt.name, func(t *testing.T) {
			files := map[string]string{"p/moul/x/x.gno": "package x\n"}
			if tt.readme != "" {
				files["p/moul/x/README.md"] = tt.readme
			}
			err := cmdGuardReadmes(fixture(t, files), nil)
			if tt.ok && err != nil {
				t.Fatalf("rejected a legal README: %v", err)
			}
			if !tt.ok && err == nil {
				t.Fatal("accepted a README that documents nothing")
			}
		})
	}
}

// Archived packages are skipped by every other guard; this one too.
func TestGuardReadmesSkipsArchivedPackages(t *testing.T) {
	root := fixture(t, map[string]string{
		"p/moul/old/gnomod.toml": "module = \"gno.land/p/moul/old\"\ngno = \"0.9\"\nignore = true\n",
		"p/moul/old/x.gno":       "package old\n",
		"p/moul/old/README.md":   "# `gno.land/p/moul/old`\n\n_TODO: describe this package._\n",
	})
	if err := cmdGuardReadmes(root, nil); err != nil {
		t.Fatalf("archived package judged: %v", err)
	}
}

func TestReadmeRegionsExtractsOnlyGeneratedParts(t *testing.T) {
	readme := "# Title\n\nprose that a PR may edit\n\n" +
		tableBegin + "\n| a | b |\n" + tableEnd + "\n\n" +
		"## Prose section\n\nmore prose\n\n" +
		graphHeading + "\n\n![graph](_assets/g.svg)\n\n" +
		"## After\n\ntail prose\n"

	got := readmeRegions(readme)
	for _, want := range []string{"| a | b |", "![graph](_assets/g.svg)"} {
		if !strings.Contains(got, want) {
			t.Fatalf("regions missing %q:\n%s", want, got)
		}
	}
	for _, unwanted := range []string{"prose that a PR may edit", "more prose", "tail prose"} {
		if strings.Contains(got, unwanted) {
			t.Fatalf("regions leaked prose %q:\n%s", unwanted, got)
		}
	}

	// Editing prose leaves the regions identical: that is what lets a PR fix a
	// stale paragraph without tripping the guard.
	edited := strings.Replace(readme, "more prose", "corrected prose", 1)
	if readmeRegions(edited) != got {
		t.Fatal("a prose-only edit changed the generated regions")
	}
	// Editing the table does not.
	touched := strings.Replace(readme, "| a | b |", "| a | c |", 1)
	if readmeRegions(touched) == got {
		t.Fatal("a table edit went undetected")
	}
}

func TestReadmeRegionsHandlesAMissingFile(t *testing.T) {
	if got := readmeRegions(""); got != "" {
		t.Fatalf("empty README yielded %q", got)
	}
}

// writeFileAt writes a file under root, creating parent directories.
func writeFileAt(t *testing.T, root, rel, body string) {
	t.Helper()
	full := filepath.Join(root, filepath.FromSlash(rel))
	if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(full, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	if strings.HasSuffix(rel, ".gno") {
		gm := filepath.Join(filepath.Dir(full), "gnomod.toml")
		if !fileExists(gm) {
			dir := filepath.ToSlash(filepath.Dir(rel))
			if err := os.WriteFile(gm, []byte("module = \"gno.land/"+dir+"\"\ngno = \"0.9\"\n"), 0o644); err != nil {
				t.Fatal(err)
			}
		}
	}
}

// gitCommit stages everything and commits it.
func gitCommit(t *testing.T, root, msg string) {
	t.Helper()
	for _, args := range [][]string{{"add", "-A"}, {"commit", "-qm", msg}} {
		cmd := exec.Command("git", append([]string{"-C", root}, args...)...)
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
	}
}
