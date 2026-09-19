package wiki

import "strings"

// DiffOp is what happened to one line between two revisions.
type DiffOp uint8

const (
	OpEqual DiffOp = iota
	OpInsert
	OpDelete
)

// DiffLine is one line of a rendered diff.
type DiffLine struct {
	Op   DiffOp
	Text string
}

// DiffMaxLines bounds the changed region a diff will compute exactly.
//
// The cost of an LCS over the changed region is O(n*m), and this runs inside
// vm/qrender, which has a gas ceiling a reader cannot raise. 80 lines caps the
// table at 6,400 cells; beyond it, a diff degrades to "this block was replaced"
// rather than making the page unrenderable. Both revisions are still available
// in full through the raw view, so nothing is hidden by the degradation.
const DiffMaxLines = 80

// TODO(#140 Q5): decide whether diffing belongs on chain at all. Both options
// are still open: keep this bounded server-side diff, or drop it and let
// clients diff two /raw responses themselves, which costs the chain nothing
// and removes DiffMaxLines entirely. Keeping it for now because a diff a
// reader can reach from a plain URL is most of what makes a history readable,
// and 691M gas at the body cap leaves room. Revisit if MaxBody ever rises.

// DiffLines compares two bodies line by line.
//
// exact reports whether the result is a real line diff. When it is false the
// changed region was larger than DiffMaxLines and the result is the coarse
// form: every removed line, then every added line.
func DiffLines(older, newer string) (out []DiffLine, exact bool) {
	a := splitLines(older)
	b := splitLines(newer)

	// Trim the common prefix and suffix. Ordinary wiki edits touch a few
	// lines of a long article, so this alone brings almost every real diff
	// under the exact-computation bound.
	head := 0
	for head < len(a) && head < len(b) && a[head] == b[head] {
		head++
	}
	tailA, tailB := len(a), len(b)
	for tailA > head && tailB > head && a[tailA-1] == b[tailB-1] {
		tailA--
		tailB--
	}

	midA := a[head:tailA]
	midB := b[head:tailB]

	out = []DiffLine{}
	for _, l := range a[:head] {
		out = append(out, DiffLine{OpEqual, l})
	}

	exact = len(midA) <= DiffMaxLines && len(midB) <= DiffMaxLines
	if exact {
		out = append(out, lcsDiff(midA, midB)...)
	} else {
		for _, l := range midA {
			out = append(out, DiffLine{OpDelete, l})
		}
		for _, l := range midB {
			out = append(out, DiffLine{OpInsert, l})
		}
	}

	for _, l := range a[tailA:] {
		out = append(out, DiffLine{OpEqual, l})
	}
	return out, exact
}

// DiffStat counts added and removed lines.
func DiffStat(lines []DiffLine) (added, removed int) {
	for _, l := range lines {
		switch l.Op {
		case OpInsert:
			added++
		case OpDelete:
			removed++
		}
	}
	return added, removed
}

// lcsDiff is the textbook longest-common-subsequence diff, bounded by the
// caller to DiffMaxLines on each side.
func lcsDiff(a, b []string) []DiffLine {
	n, m := len(a), len(b)
	if n == 0 && m == 0 {
		return []DiffLine{}
	}
	// table[i][j] is the LCS length of a[i:] and b[j:].
	table := make([][]int, n+1)
	for i := range table {
		table[i] = make([]int, m+1)
	}
	for i := n - 1; i >= 0; i-- {
		for j := m - 1; j >= 0; j-- {
			if a[i] == b[j] {
				table[i][j] = table[i+1][j+1] + 1
			} else if table[i+1][j] >= table[i][j+1] {
				table[i][j] = table[i+1][j]
			} else {
				table[i][j] = table[i][j+1]
			}
		}
	}

	out := []DiffLine{}
	i, j := 0, 0
	for i < n && j < m {
		switch {
		case a[i] == b[j]:
			out = append(out, DiffLine{OpEqual, a[i]})
			i++
			j++
		case table[i+1][j] >= table[i][j+1]:
			out = append(out, DiffLine{OpDelete, a[i]})
			i++
		default:
			out = append(out, DiffLine{OpInsert, b[j]})
			j++
		}
	}
	for ; i < n; i++ {
		out = append(out, DiffLine{OpDelete, a[i]})
	}
	for ; j < m; j++ {
		out = append(out, DiffLine{OpInsert, b[j]})
	}
	return out
}

func splitLines(s string) []string {
	if s == "" {
		return []string{}
	}
	s = strings.TrimSuffix(s, "\n")
	return strings.Split(s, "\n")
}
