package wiki

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// render turns a diff into the compact "+a -b =c" form the tests assert on.
func render(lines []DiffLine) string {
	var b strings.Builder
	for _, l := range lines {
		switch l.Op {
		case OpInsert:
			b.WriteString("+")
		case OpDelete:
			b.WriteString("-")
		default:
			b.WriteString("=")
		}
		b.WriteString(l.Text)
		b.WriteString(";")
	}
	return b.String()
}

func TestDiffLines(t *testing.T) {
	cases := []struct {
		name     string
		old, new string
		want     string
	}{
		{"identical", "a\nb\n", "a\nb\n", "=a;=b;"},
		{"append", "a\n", "a\nb\n", "=a;+b;"},
		{"prepend", "b\n", "a\nb\n", "+a;=b;"},
		{"delete", "a\nb\n", "a\n", "=a;-b;"},
		{"replace middle", "a\nb\nc\n", "a\nx\nc\n", "=a;-b;+x;=c;"},
		{"from empty", "", "a\n", "+a;"},
		{"to empty", "a\n", "", "-a;"},
		{"both empty", "", "", ""},
		{"no trailing newline", "a\nb", "a\nc", "=a;-b;+c;"},
	}
	for _, tc := range cases {
		got, exact := DiffLines(tc.old, tc.new)
		uassert.True(t, exact, tc.name+" must be exact")
		uassert.Equal(t, tc.want, render(got), tc.name)
	}
}

func TestDiffStat(t *testing.T) {
	lines, _ := DiffLines("a\nb\nc\n", "a\nx\ny\nc\n")
	added, removed := DiffStat(lines)
	uassert.Equal(t, 2, added)
	uassert.Equal(t, 1, removed)
}

// TestDiffCommonPrefixKeepsLongArticlesExact is the property that makes the
// DiffMaxLines bound usable in practice: a one-line edit to a 500-line article
// still diffs exactly, because only the changed region is fed to the LCS.
func TestDiffCommonPrefixKeepsLongArticlesExact(t *testing.T) {
	var b strings.Builder
	for i := 0; i < 500; i++ {
		b.WriteString("line\n")
	}
	old := b.String()
	updated := old + "added\n"

	lines, exact := DiffLines(old, updated)
	uassert.True(t, exact, "a one-line change to a 500-line article must diff exactly")
	added, removed := DiffStat(lines)
	uassert.Equal(t, 1, added)
	uassert.Equal(t, 0, removed)
}

// TestDiffDegradesInsteadOfBlowingTheGasBudget locks the documented fallback:
// past DiffMaxLines the diff becomes a block replacement rather than an
// unrenderable page.
func TestDiffDegradesInsteadOfBlowingTheGasBudget(t *testing.T) {
	var a, b strings.Builder
	for i := 0; i < DiffMaxLines+1; i++ {
		a.WriteString("old\n")
		b.WriteString("new\n")
	}
	lines, exact := DiffLines(a.String(), b.String())
	uassert.False(t, exact, "past the bound the diff must report itself inexact")
	added, removed := DiffStat(lines)
	uassert.Equal(t, DiffMaxLines+1, added)
	uassert.Equal(t, DiffMaxLines+1, removed)
}
