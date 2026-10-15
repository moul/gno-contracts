package myersdiff

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// render turns a script into one compact string per line, so a table case can
// state the whole expected script as text instead of a slice literal.
func render(s Script) string {
	var sb strings.Builder
	for i, e := range s.Edits {
		if i > 0 {
			sb.WriteString("|")
		}
		sb.WriteString(e.Op.String())
		sb.WriteString(e.Line)
	}
	return sb.String()
}

func TestScript(t *testing.T) {
	cases := []struct {
		name string
		a    string
		b    string
		want string
	}{
		{"identical", "a\nb\nc", "a\nb\nc", " a| b| c"},
		{"both empty", "", "", ""},
		{"insert into empty", "", "a\nb", "+a|+b"},
		{"delete to empty", "a\nb", "", "-a|-b"},
		{"append one", "a", "a\nb", " a|+b"},
		{"prepend one", "b", "a\nb", "+a| b"},
		{"substitute middle", "a\nb\nc", "a\nx\nc", " a|-b|+x| c"},
		{"delete middle", "a\nb\nc", "a\nc", " a|-b| c"},
		{"nothing in common", "a\nb", "x\ny", "-a|-b|+x|+y"},
		{"trailing newline is a line", "a", "a\n", " a|+"},
		{"move one line down", "a\nb\nc", "b\nc\na", "-a| b| c|+a"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := Lines(tc.a, tc.b)
			uassert.True(t, got.Minimal, "expected a minimal script")
			uassert.Equal(t, tc.want, render(got))
		})
	}
}

// TestScriptIsShortest is the property the algorithm exists for. A correct but
// lazy implementation (delete everything, insert everything) passes every
// round-trip test, so the count of changed lines is asserted separately.
func TestScriptIsShortest(t *testing.T) {
	cases := []struct {
		name    string
		a       string
		b       string
		changed int
	}{
		{"one substitution", "a\nb\nc", "a\nx\nc", 2},
		{"one insertion", "a\nb\nc", "a\nb\nx\nc", 1},
		{"one deletion", "a\nb\nc", "a\nc", 1},
		{"two far apart", "a\nb\nc\nd\ne", "x\nb\nc\nd\ny", 4},
		{"classic abcabba to cbabac", "a\nb\nc\na\nb\nb\na", "c\nb\na\nb\na\nc", 5},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			s := Lines(tc.a, tc.b)
			changed := s.Added() + s.Deleted()
			uassert.Equal(t, tc.changed, changed)
		})
	}
}

// TestApplyRoundTrips is the correctness half: whatever script comes out, it
// has to turn a back into b. Checked on the minimal path and on the budget
// fallback, because the fallback is the one nobody looks at.
func TestApplyRoundTrips(t *testing.T) {
	cases := []struct {
		name   string
		a      string
		b      string
		budget int
	}{
		{"typical patch", "one\ntwo\nthree\nfour", "one\n2\nthree\nfour\nfive", 0},
		{"full rewrite", "a\nb\nc\nd", "w\nx\ny\nz", 0},
		{"starved budget", "a\nb\nc\nd", "w\nx\ny\nz", 1},
		{"empty to empty", "", "", 0},
		{"repeated lines", "x\nx\nx\nx", "x\nx", 0},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			s := Budget(split(tc.a), split(tc.b), tc.budget)
			got := strings.Join(s.Apply(split(tc.a)), "\n")
			uassert.Equal(t, tc.b, got)
		})
	}
}

// TestBudgetFallback pins what a starved search returns. The script stops being
// minimal and says so; it does not stop being correct and it does not panic.
func TestBudgetFallback(t *testing.T) {
	a := split("a\nb\nc\nd\ne\nf")
	b := split("u\nv\nw\nx\ny\nz")

	starved := Budget(a, b, 2)
	uassert.False(t, starved.Minimal, "a two-round budget cannot reach a 12-edit script")
	uassert.Equal(t, 6, starved.Deleted())
	uassert.Equal(t, 6, starved.Added())
	uassert.Equal(t, 0, starved.Unchanged())

	full := Budget(a, b, 0)
	uassert.True(t, full.Minimal, "the default budget is enough for six lines")
	uassert.Equal(t, strings.Join(b, "\n"), strings.Join(full.Apply(a), "\n"))

	// A budget above what the script needs changes nothing, and a budget larger
	// than any possible script is not an error.
	wide := Budget(a, b, 10000)
	uassert.True(t, wide.Minimal, "an oversized budget still terminates")
	uassert.Equal(t, render(full), render(wide))
}

func TestCounts(t *testing.T) {
	s := Lines("a\nb\nc", "a\nx\ny\nc")
	uassert.Equal(t, 2, s.Added())
	uassert.Equal(t, 1, s.Deleted())
	uassert.Equal(t, 2, s.Unchanged())
}

func TestHunks(t *testing.T) {
	// Eleven lines, two changes far enough apart to stay separate at context 1
	// and to merge at context 3.
	a := "1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11"
	b := "1\n2\nX\n4\n5\n6\n7\n8\nY\n10\n11"
	s := Lines(a, b)

	narrow := Hunks(s, 1)
	uassert.Equal(t, 2, len(narrow))
	uassert.Equal(t, "@@ -2,3 +2,3 @@", narrow[0].Header())
	uassert.Equal(t, "@@ -8,3 +8,3 @@", narrow[1].Header())

	wide := Hunks(s, 3)
	uassert.Equal(t, 1, len(wide))
	uassert.Equal(t, "@@ -1,11 +1,11 @@", wide[0].Header())

	none := Hunks(Lines(a, a), 3)
	uassert.Equal(t, 0, len(none))

	zero := Hunks(s, 0)
	uassert.Equal(t, 2, len(zero))
	uassert.Equal(t, "@@ -3 +3 @@", zero[0].Header())
}

// TestHunkHeaderEmptySide pins the one header convention that is not obvious:
// a side contributing no lines reports the line before the hunk and a length of
// zero, which is what diff(1) prints and what patch(1) expects to read back.
func TestHunkHeaderEmptySide(t *testing.T) {
	into := Hunks(Lines("", "a\nb"), 0)
	uassert.Equal(t, 1, len(into))
	uassert.Equal(t, "@@ -0,0 +1,2 @@", into[0].Header())

	outOf := Hunks(Lines("a\nb", ""), 0)
	uassert.Equal(t, 1, len(outOf))
	uassert.Equal(t, "@@ -1,2 +0,0 @@", outOf[0].Header())

	negative := Hunks(Lines("a", "b"), -5)
	uassert.Equal(t, 1, len(negative))
	uassert.Equal(t, "@@ -1 +1 @@", negative[0].Header())
}

func TestUnified(t *testing.T) {
	a := "the quick\nbrown fox\njumps over\nthe lazy dog"
	b := "the quick\nred fox\njumps over\nthe lazy dog\nand runs"

	want := "@@ -1,4 +1,5 @@\n the quick\n-brown fox\n+red fox\n jumps over\n the lazy dog\n+and runs\n"
	uassert.Equal(t, want, Unified(a, b, 3))

	uassert.Equal(t, "", Unified(a, a, 3))
	uassert.Equal(t, Unified(a, b, 3), UnifiedScript(Lines(a, b), 3))
}

func TestOpString(t *testing.T) {
	uassert.Equal(t, "-", Delete.String())
	uassert.Equal(t, " ", Equal.String())
	uassert.Equal(t, "+", Insert.String())
}

func TestMaxLines(cur realm, t *testing.T) {
	big := make([]string, MaxLines+1)
	ok := make([]string, MaxLines)
	uassert.PanicsWithMessage(t, cur, "myersdiff: input exceeds MaxLines", func() { Budget(big, ok, 0) })
	uassert.PanicsWithMessage(t, cur, "myersdiff: input exceeds MaxLines", func() { Budget(ok, big, 0) })
	// MaxLines identical lines is the cheap case: d is zero, so the search ends
	// in the first round whatever the size.
	uassert.NotPanics(t, cur, func() { Budget(ok, ok, 0) })
}
