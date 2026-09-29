package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// tableFixture writes one package holding one .gno file.
func tableFixture(t *testing.T, dir, body string) string {
	t.Helper()
	root := t.TempDir()
	full := filepath.Join(root, filepath.FromSlash(dir))
	if err := os.MkdirAll(full, 0o755); err != nil {
		t.Fatal(err)
	}
	writeFile(t, full, "gnomod.toml", mod("gno.land/"+dir+"/v0"))
	writeFile(t, full, "x.gno", body)
	return root
}

const handRolled = "package x\n\nfunc Render(p string) string {\n" +
	"\treturn \"| a | b |\\n|---|---|\\n\"\n}\n"

const viaKit = "package x\n\nfunc Render(p string) string {\n" +
	"\tt := ui.NewTable(\"a\", \"b\")\n\treturn t.String()\n}\n"

func TestGuardTablesFlagsAHandRolledSeparator(t *testing.T) {
	root := tableFixture(t, "r/moul/hand", handRolled)
	err := cmdGuardTables(root, nil)
	if err == nil {
		t.Fatal("want a failure for a hand-rolled table, got nil")
	}
	if !strings.Contains(err.Error(), "r/moul/hand") {
		t.Fatalf("want the package named, got %v", err)
	}
}

func TestGuardTablesPassesWhenTheTableComesFromKitUI(t *testing.T) {
	root := tableFixture(t, "r/moul/kitted", viaKit)
	if err := cmdGuardTables(root, nil); err != nil {
		t.Fatalf("a kit/ui table is the fix, not a finding: %v", err)
	}
}

// The alignment forms and a spaced separator are all GFM; a horizontal rule and
// a run of dashes inside a word are not.
func TestGuardTablesSeparatorDetection(t *testing.T) {
	for _, tc := range []struct {
		lit  string
		want bool
	}{
		{`"|---|---|"`, true},
		{`"| --- | --- |"`, true},
		{`"|:---|---:|"`, true},
		{`" --- |"`, true},
		{`"---"`, false},
		{`"a---b"`, false},
		{`"--"`, false},
	} {
		if got := tableSepRe.MatchString(tc.lit); got != tc.want {
			t.Errorf("tableSepRe.MatchString(%s) = %v, want %v", tc.lit, got, tc.want)
		}
	}
}

// The opt-out is for dashes that are not a table at all: p/moul/x/daily/cowsay's
// cow has "||----w |" for a horn.
func TestGuardTablesHonoursAnOptOutWithARealReason(t *testing.T) {
	root := tableFixture(t, "r/moul/art",
		"package x\n\n// handrolled-table: ASCII art, the dashes are a cow's horn, no table here\n"+
			"const cow = \"||----w |\"\n")
	if err := cmdGuardTables(root, nil); err != nil {
		t.Fatalf("a real reason is the opt-out: %v", err)
	}
}

func TestGuardTablesRejectsAThinOptOutReason(t *testing.T) {
	root := tableFixture(t, "r/moul/art",
		"package x\n\n// handrolled-table: n/a\nconst cow = \"||----w |\"\n")
	err := cmdGuardTables(root, nil)
	if err == nil || !strings.Contains(err.Error(), "answer nothing") {
		t.Fatalf("want the thin-reason failure, got %v", err)
	}
}

// A grandfathered package that gets fixed has to leave the baseline, or it
// silences the next package that starts.
func TestGuardTablesFailsOnAStaleBaselineEntry(t *testing.T) {
	root := tableFixture(t, "r/moul/hand", handRolled)
	if err := cmdGuardTables(root, []string{"-update"}); err != nil {
		t.Fatal(err)
	}
	if err := cmdGuardTables(root, nil); err != nil {
		t.Fatalf("recorded, so it should pass: %v", err)
	}

	writeFile(t, filepath.Join(root, "r", "moul", "hand"), "x.gno", viaKit)
	err := cmdGuardTables(root, nil)
	if err == nil || !strings.Contains(err.Error(), "no longer apply") {
		t.Fatalf("want the stale-entry failure, got %v", err)
	}
}

// An opted-out package must not ALSO sit in the baseline: two records for one
// package means neither goes stale when it is fixed.
func TestGuardTablesUpdateExcludesOptedOutPackages(t *testing.T) {
	root := tableFixture(t, "r/moul/art",
		"package x\n\n// handrolled-table: ASCII art, the dashes are a cow's horn, no table here\n"+
			"const cow = \"||----w |\"\n")
	if err := cmdGuardTables(root, []string{"-update"}); err != nil {
		t.Fatal(err)
	}
	b, err := os.ReadFile(filepath.Join(root, tableBaselineFile))
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(b), "r/moul/art") {
		t.Fatalf("an opted-out package belongs in the code, not the baseline:\n%s", b)
	}
}

// A package whose production source is already live on an immutable public path
// can never be edited again, so its test file is the only place a true opt-out
// can still be written. This is p/moul/x/daily/cowsay's case exactly.
func TestGuardTablesReadsAnOptOutFromATestFile(t *testing.T) {
	root := tableFixture(t, "r/moul/art",
		"package x\n\nconst cow = \"||----w |\"\n")
	writeFile(t, filepath.Join(root, "r", "moul", "art"), "x_test.gno",
		"package x\n\n// handrolled-table: ASCII art, the dashes are a cow's horn, no table here\n")
	if err := cmdGuardTables(root, nil); err != nil {
		t.Fatalf("an opt-out in a test file counts: %v", err)
	}
}

// The reverse must not hold: a test's own dashes are a fixture, not a page, and
// counting them would flag every package that tests a renderer.
func TestGuardTablesIgnoresASeparatorInATestFile(t *testing.T) {
	root := tableFixture(t, "r/moul/tested", cleanSrc)
	writeFile(t, filepath.Join(root, "r", "moul", "tested"), "x_test.gno",
		"package x\n\nconst want = \"| a | b |\\n|---|---|\\n\"\n")
	if err := cmdGuardTables(root, nil); err != nil {
		t.Fatalf("a separator inside a test is a fixture, not a finding: %v", err)
	}
}
