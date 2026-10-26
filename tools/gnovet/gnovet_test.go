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

// A Bad that fires at all is not enough when one fixture carries several
// shapes: each of these was a gap a review found, and each must fire on its
// own, or a regression in one hides behind the others.
func TestEveryShapeInAMultiShapeBadFires(t *testing.T) {
	for _, tc := range []struct {
		rule Rule
		want int
	}{
		// []address, a struct, a named slice, a multiline signature
		{uncallableCrossingArg, 4},
		// no guard at all, and a guard that comes after the read
		{originSendUnguarded, 2},
		// (page - 1) * size, and the other operand order
		{pageOffsetOverflow, 2},
	} {
		hits, err := RunRules(write(t, "bad.gno", tc.rule.Bad), []Rule{tc.rule})
		if err != nil {
			t.Fatal(err)
		}
		if len(hits) != tc.want {
			t.Errorf("%s: %d hit(s) on its Bad, want %d: %v", tc.rule.ID, len(hits), tc.want, hits)
		}
	}
}

// The vendor skip is root-relative. A package under p/<ns>/vendor/ is written
// here and published as ours, so it must still be scanned; only a vendor/
// directory at the repository root is third-party. An earlier version matched
// "/vendor/" anywhere and silently dropped p/moul/vendor/nt/ufmt.
func TestVendorSkipIsRootRelative(t *testing.T) {
	dir := t.TempDir()
	body := []byte(trimSpaceAsValidity.Bad)
	for _, rel := range []string{
		"vendor/third/party.gno",    // root vendor: skipped
		"p/moul/vendor/nt/ours.gno", // our namespace: scanned
	} {
		p := filepath.Join(dir, rel)
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, body, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	hits, err := RunRules(dir, []Rule{trimSpaceAsValidity})
	if err != nil {
		t.Fatal(err)
	}
	var got []string
	for _, h := range hits {
		got = append(got, filepath.ToSlash(h.File))
	}
	if len(got) != 1 || got[0] != "p/moul/vendor/nt/ours.gno" {
		t.Fatalf("want only p/moul/vendor/nt/ours.gno scanned, got %v", got)
	}
}

// The same presence check is more often written in two statements, the value
// trimmed into a variable and the variable compared to "". The one-line regexp
// never sees it, which is how five realms kept accepting zero-width-only input
// after the one-line sites were fixed. Only a REQUIRED field fires: the
// comparison has to reject with a panic. A Render path that falls back to its
// index, a list parser that skips an empty element and a default value are the
// same two statements and a different question, so they stay silent. Each row
// is one spelling; want is the number of hits.
func TestTrimSpaceValidityCatchesTheTwoStatementSpelling(t *testing.T) {
	for _, tc := range []struct {
		name string
		body string
		want int
	}{
		{"define then compare", "msg := strings.TrimSpace(message)\n\tif msg == \"\" {\n\t\tpanic(\"empty\")\n\t}", 1},
		{"assign then compare", "name = strings.TrimSpace(name)\n\tif name == \"\" {\n\t\tpanic(\"empty\")\n\t}", 1},
		{"reversed operands", "q := strings.TrimSpace(s)\n\tif \"\" == q {\n\t\tpanic(\"empty\")\n\t}", 1},
		{"one statement between", "title = strings.TrimSpace(title)\n\tbody = strings.TrimSpace(body)\n\tif title == \"\" {\n\t\tpanic(\"empty\")\n\t}", 1},
		{"blank line between", "target := strings.TrimSpace(p)\n\n\tif target == \"\" {\n\t\tpanic(\"empty\")\n\t}", 1},
		{"nested call inside TrimSpace", "p := strings.TrimSpace(strings.Trim(path, \"/\"))\n\tif p == \"\" {\n\t\tpanic(\"empty\")\n\t}", 1},
		{"second of two trims, checked after the first", "title = strings.TrimSpace(title)\n\tbody = strings.TrimSpace(body)\n\tif title == \"\" {\n\t\tpanic(\"empty\")\n\t}\n\tif body == \"\" {\n\t\tpanic(\"empty\")\n\t}", 2},
		{"panic on the same line", "s := strings.TrimSpace(raw)\n\tif s == \"\" { panic(\"empty\") }", 1},
		{"the one-line form still fires once", "if strings.TrimSpace(s) == \"\" {\n\t\tpanic(\"empty\")\n\t}", 1},

		{"the fix: compare the stripped form", "msg := strings.TrimSpace(message)\n\tif strings.TrimSpace(markdown.StripBidiAndZeroWidth(msg)) == \"\" {\n\t\tpanic(\"empty\")\n\t}", 0},
		{"reassigned before the compare", "s := strings.TrimSpace(raw)\n\ts = markdown.StripBidiAndZeroWidth(s)\n\tif s == \"\" {\n\t\tpanic(\"empty\")\n\t}", 0},
		{"a different variable compared", "s := strings.TrimSpace(raw)\n\tif t == \"\" {\n\t\tpanic(\"empty\")\n\t}", 0},
		{"a prefix of the name compared", "msg := strings.TrimSpace(raw)\n\tif msgs == \"\" {\n\t\tpanic(\"empty\")\n\t}", 0},
		{"compared far below", "s := strings.TrimSpace(raw)\n\ta()\n\tb()\n\tc()\n\td()\n\te()\n\tif s == \"\" {\n\t\tpanic(\"empty\")\n\t}", 0},
		{"no TrimSpace at all", "s := raw\n\tif s == \"\" {\n\t\tpanic(\"empty\")\n\t}", 0},
		{"render path falls back to the index", "path = strings.TrimSpace(path)\n\tif path == \"\" {\n\t\treturn renderIndex()\n\t}", 0},
		{"list parser skips an empty element", "raw = strings.TrimSpace(raw)\n\tif raw == \"\" {\n\t\tcontinue\n\t}", 0},
		{"keeps a non-empty element", "o := strings.TrimSpace(raw)\n\tif o != \"\" {\n\t\tout = append(out, o)\n\t}", 0},
		{"default value", "name = strings.TrimSpace(name)\n\tif name == \"\" {\n\t\tname = \"world\"\n\t}", 0},
		{"not-empty then panic is not a presence check", "s := strings.TrimSpace(raw)\n\tif s != \"\" {\n\t\tpanic(\"must be empty\")\n\t}", 0},
	} {
		t.Run(tc.name, func(t *testing.T) {
			src := "package x\n\nfunc f(message, name, raw, s, path, p, title, body string) {\n\t" + tc.body + "\n}\n"
			hits, err := RunRules(write(t, "x.gno", src), []Rule{trimSpaceAsValidity})
			if err != nil {
				t.Fatal(err)
			}
			if len(hits) != tc.want {
				t.Errorf("%d hit(s), want %d: %v\n--- source ---\n%s", len(hits), tc.want, hits, src)
			}
		})
	}
}

// RenderPathRaw lives outside Rules because it runs in an audit family's slot,
// so the two contracts every rule signs have to be checked for it by name.
func TestRenderPathRawSignsTheRuleContract(t *testing.T) {
	r := RenderPathRaw
	if len(r.Finding) < 20 || r.What == "" || r.Why == "" || r.Fix == "" {
		t.Fatalf("%s is missing a required field", r.ID)
	}
	if _, dup := ByID(r.ID); dup {
		t.Fatalf("%s is also in Rules, so it would run twice", r.ID)
	}
	bad, err := RunRules(write(t, "bad.gno", r.Bad), []Rule{r})
	if err != nil {
		t.Fatal(err)
	}
	if len(bad) != 1 || bad[0].Text != "b.WriteString(q)" {
		t.Fatalf("the Bad fixture should fire once, on the raw write: %v", bad)
	}
	good, err := RunRules(write(t, "good.gno", r.Good), []Rule{r})
	if err != nil {
		t.Fatal(err)
	}
	if len(good) != 0 {
		t.Fatalf("the Good fixture fires at %v", good)
	}
}

// Taint is scoped to the func that derived it. The file-wide version tainted
// every `s` in the file once Render had one, and fired on 189 lines of this
// tree, most of them a stored record's fields.
func TestRenderPathRawScopesTaintToAFunc(t *testing.T) {
	for _, tc := range []struct {
		name string
		src  string
		want int
	}{
		{"same name in an unrelated func", "package x\n\n" +
			"func Render(path string) string {\n\ts := strings.TrimSpace(path)\n\treturn renderOne(len(s))\n}\n\n" +
			"func short(s string) string {\n\treturn s[:8] + \"…\"\n}\n", 0},
		{"a lookup keyed by the path returns stored data", "package x\n\n" +
			"func Render(path string) string {\n\td := duels.Get(path)\n\treturn \"# Duel \" + d.ID\n}\n", 0},
		{"taint crosses into a helper's parameter", "package x\n\n" +
			"func Render(path string) string {\n\treturn renderOne(path)\n}\n\n" +
			"func renderOne(q string) string {\n\treturn \"# \" + q + \"\\n\"\n}\n", 1},
		{"Sprintf wrapping onto the next line", "package x\n\n" +
			"func Render(path string) string {\n\treturn ufmt.Sprintf(\"Balance of `%s`\",\n\t\tpath)\n}\n", 1},
		{"an escaper ends the trail", "package x\n\n" +
			"func Render(path string) string {\n\tvar b strings.Builder\n\tb.WriteString(ui.Inline(path))\n\treturn b.String()\n}\n", 0},
		{"Render returning the path as the page", "package x\n\n" +
			"func Render(path string) string {\n\treturn path\n}\n", 1},
		{"a field named like the parameter is not it", "package x\n\n" +
			"func Render(path string) string {\n\treturn \"# \" + c.path\n}\n", 0},
	} {
		t.Run(tc.name, func(t *testing.T) {
			hits, err := RunRules(write(t, "x.gno", tc.src), []Rule{RenderPathRaw})
			if err != nil {
				t.Fatal(err)
			}
			if len(hits) != tc.want {
				t.Fatalf("want %d hit(s), got %v", tc.want, hits)
			}
		})
	}
}
