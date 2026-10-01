package gnovet

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// write drops one .gno file into a fresh directory.
func write(t *testing.T, name, body string) string {
	t.Helper()
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, name), []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	return dir
}

// The contract every rule signs: its Bad fires and its Good does not.
//
// This is the upstream audit-pattern harness's discipline and it is the only
// thing that stops a rule from quietly matching nothing after a refactor. A
// rule whose Bad stops firing is a rule that has silently switched itself off.
func TestEveryRuleFiresOnItsBadAndIsSilentOnItsGood(t *testing.T) {
	for _, r := range Rules {
		t.Run(r.ID, func(t *testing.T) {
			bad, err := RunRules(write(t, "bad.gno", r.Bad), []Rule{r})
			if err != nil {
				t.Fatal(err)
			}
			if len(bad) == 0 {
				t.Fatalf("the Bad fixture does not fire:\n%s\n--- fixture ---\n%s",
					r.Describe(), r.Bad)
			}

			good, err := RunRules(write(t, "good.gno", r.Good), []Rule{r})
			if err != nil {
				t.Fatal(err)
			}
			if len(good) != 0 {
				t.Fatalf("the Good fixture fires at %v:\n%s\n--- fixture ---\n%s",
					good, r.Describe(), r.Good)
			}
		})
	}
}

// A rule nobody can trace is a rule nobody can argue with. Every one of these
// was a real defect in real code before it was a rule, and the citation is how
// a future reader checks that claim instead of believing it.
func TestEveryRuleCitesItsFinding(t *testing.T) {
	seen := map[string]bool{}
	for _, r := range Rules {
		if r.ID == "" || r.What == "" || r.Why == "" || r.Fix == "" {
			t.Errorf("%q is missing a required field", r.ID)
		}
		if len(r.Finding) < 20 {
			t.Errorf("%s cites no finding: %q", r.ID, r.Finding)
		}
		if seen[r.ID] {
			t.Errorf("duplicate rule id %q", r.ID)
		}
		seen[r.ID] = true
	}
}

// A rule must not fire on prose. This repository's own comments discuss the
// patterns the rules look for, at length, which is exactly how a regexp over
// raw source produces a lint that cannot be satisfied.
func TestRulesDoNotFireOnCommentsOrStrings(t *testing.T) {
	src := "package x\n\n" +
		"// Never write append(s[:i], s[i+1:]...) here, and never (n + size - 1) / size.\n" +
		"const doc = \"append(s[:i], s[i+1:]...) and (n + size - 1) / size\"\n"
	hits, err := Run(write(t, "doc.gno", src))
	if err != nil {
		t.Fatal(err)
	}
	if len(hits) != 0 {
		t.Fatalf("prose and string literals must not fire: %v", hits)
	}
}

// Tests are not the deployed surface, and a test may well build the bad shape
// deliberately to assert against it.
func TestTestFilesAreNotScanned(t *testing.T) {
	dir := t.TempDir()
	for _, n := range []string{"a_test.gno", "a_filetest.gno"} {
		if err := os.WriteFile(filepath.Join(dir, n), []byte(sliceInPlaceRemove.Bad), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	hits, err := Run(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(hits) != 0 {
		t.Fatalf("test files must not be scanned: %v", hits)
	}
}

func TestIgnoreNeedsARealReason(t *testing.T) {
	body := sliceInPlaceRemove.Bad
	for _, tc := range []struct {
		name    string
		comment string
		want    int
	}{
		{"no comment", "", 1},
		{"thin reason", "//gnovet:ignore slice-inplace-remove n/a", 1},
		{"wrong rule", "//gnovet:ignore ceil-div-overflow this is a different rule entirely", 1},
		{"real reason", "//gnovet:ignore slice-inplace-remove the slice is dropped whole on the next line", 0},
	} {
		t.Run(tc.name, func(t *testing.T) {
			src := body
			if tc.comment != "" {
				src = strings.Replace(src, "\te.ids = append",
					"\t"+tc.comment+"\n\te.ids = append", 1)
			}
			hits, err := Run(write(t, "x.gno", src))
			if err != nil {
				t.Fatal(err)
			}
			if len(hits) != tc.want {
				t.Fatalf("want %d hit(s), got %d: %v", tc.want, len(hits), hits)
			}
		})
	}
}

// The ignore must also work on the line itself, not only the line above.
func TestIgnoreWorksOnTheSameLine(t *testing.T) {
	src := strings.Replace(sliceInPlaceRemove.Bad,
		"e.ids[pos+1:]...)",
		"e.ids[pos+1:]...) //gnovet:ignore slice-inplace-remove the whole slice is dropped right after",
		1)
	hits, err := Run(write(t, "x.gno", src))
	if err != nil {
		t.Fatal(err)
	}
	if len(hits) != 0 {
		t.Fatalf("a same-line ignore must count: %v", hits)
	}
}

// append(a[:i], b[i+1:]...) with two DIFFERENT slices is a concatenation, not a
// removal, and flagging it would be the false positive that gets the rule
// switched off.
func TestSliceRemoveNeedsTheSameSliceOnBothSides(t *testing.T) {
	src := "package x\n\nfunc f() {\n\tout = append(head[:n], tail[n+1:]...)\n}\n"
	hits, err := Run(write(t, "x.gno", src))
	if err != nil {
		t.Fatal(err)
	}
	if len(hits) != 0 {
		t.Fatalf("two different slices is a concatenation: %v", hits)
	}
}

// Likewise (a + b - 1) / c is not a ceiling division.
func TestCeilDivNeedsTheSameDivisor(t *testing.T) {
	src := "package x\n\nfunc f(n, size, other int) int {\n\treturn (n + size - 1) / other\n}\n"
	hits, err := Run(write(t, "x.gno", src))
	if err != nil {
		t.Fatal(err)
	}
	if len(hits) != 0 {
		t.Fatalf("a different divisor is not a ceiling: %v", hits)
	}
}

// The avl rule is the one that reads Raw, because an import path is a string
// literal and the blanked view has nothing in it. A mention of avl in prose
// must still not fire.
func TestAvlRuleReadsImportsAndNotProse(t *testing.T) {
	prose := "package x\n\n// We used to import gno.land/p/nt/avl/v0 here and it cost 2,029 B/entry.\n" +
		"const s = \"gno.land/p/nt/avl/v0\"\n"
	hits, err := Run(write(t, "x.gno", prose))
	if err != nil {
		t.Fatal(err)
	}
	if len(hits) != 0 {
		t.Fatalf("prose and a non-import string must not fire: %v", hits)
	}

	block := "package x\n\nimport (\n\t\"strings\"\n\n\t\"gno.land/p/nt/avl/v0\"\n)\n"
	hits, err = Run(write(t, "y.gno", block))
	if err != nil {
		t.Fatal(err)
	}
	if len(hits) != 1 || hits[0].Rule != "avl-in-new-code" {
		t.Fatalf("an import inside a block must fire once: %v", hits)
	}
}

func TestByID(t *testing.T) {
	if _, ok := ByID("slice-inplace-remove"); !ok {
		t.Error("a known rule must resolve")
	}
	if _, ok := ByID("no-such-rule"); ok {
		t.Error("an unknown rule must not")
	}
}
