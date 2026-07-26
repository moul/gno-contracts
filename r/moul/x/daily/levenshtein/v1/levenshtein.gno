// Package levenshtein ports the classic Levenshtein edit-distance algorithm
// (as found in Go libraries like agext/levenshtein) to a gno.land realm.
//
// The core is the textbook dynamic-programming matrix: the minimum number of
// single-character insertions, deletions, or substitutions to turn string a
// into string b. It is fully rune-aware and pure (deterministic), so it runs
// happily on-chain.
package levenshtein

import (
	"strconv"
	"strings"
)

// Distance returns the Levenshtein edit distance between a and b.
//
// It counts single-rune insertions, deletions, and substitutions and works on
// runes (not bytes), so multi-byte UTF-8 input is handled correctly. The
// classic two-row DP is used, so memory is O(min(len)) and time is O(len(a)*len(b)).
func Distance(a, b string) int {
	ra := []rune(a)
	rb := []rune(b)

	// Keep the shorter slice as the inner (column) dimension.
	if len(ra) < len(rb) {
		ra, rb = rb, ra
	}
	n := len(ra)
	m := len(rb)
	if m == 0 {
		return n
	}

	// prev[j] = distance between ra[:i] and rb[:j].
	prev := make([]int, m+1)
	for j := 0; j <= m; j++ {
		prev[j] = j
	}
	curr := make([]int, m+1)

	for i := 1; i <= n; i++ {
		curr[0] = i
		for j := 1; j <= m; j++ {
			cost := 1
			if ra[i-1] == rb[j-1] {
				cost = 0
			}
			curr[j] = min3(
				curr[j-1]+1,    // insertion
				prev[j]+1,      // deletion
				prev[j-1]+cost, // substitution / match
			)
		}
		prev, curr = curr, prev
	}
	return prev[m]
}

// Matrix returns the full (len(a)+1) x (len(b)+1) DP matrix used by Distance.
// matrix[i][j] is the edit distance between the first i runes of a and the
// first j runes of b. The bottom-right cell equals Distance(a, b).
func Matrix(a, b string) [][]int {
	ra := []rune(a)
	rb := []rune(b)
	n := len(ra)
	m := len(rb)

	d := make([][]int, n+1)
	for i := 0; i <= n; i++ {
		d[i] = make([]int, m+1)
		d[i][0] = i
	}
	for j := 0; j <= m; j++ {
		d[0][j] = j
	}
	for i := 1; i <= n; i++ {
		for j := 1; j <= m; j++ {
			cost := 1
			if ra[i-1] == rb[j-1] {
				cost = 0
			}
			d[i][j] = min3(d[i][j-1]+1, d[i-1][j]+1, d[i-1][j-1]+cost)
		}
	}
	return d
}

// Similarity returns a 0..100 percentage of how similar a and b are, defined as
// (1 - distance/maxLen) * 100 rounded to the nearest integer. Two empty strings
// are considered 100% similar.
func Similarity(a, b string) int {
	la := len([]rune(a))
	lb := len([]rune(b))
	maxLen := la
	if lb > maxLen {
		maxLen = lb
	}
	if maxLen == 0 {
		return 100
	}
	dist := Distance(a, b)
	// Rounded percentage of matching characters.
	return ((maxLen-dist)*100 + maxLen/2) / maxLen
}

func min3(a, b, c int) int {
	m := a
	if b < m {
		m = b
	}
	if c < m {
		m = c
	}
	return m
}

// renderTable formats the DP matrix as a Markdown table with a and b as headers.
func renderTable(a, b string) string {
	ra := []rune(a)
	rb := []rune(b)
	d := Matrix(a, b)

	var sb strings.Builder
	// Header row: blank | "" | each rune of b.
	sb.WriteString("|   | ε |")
	for _, r := range rb {
		sb.WriteString(" `")
		sb.WriteString(string(r))
		sb.WriteString("` |")
	}
	sb.WriteString("\n")
	// Separator.
	sb.WriteString("|---|")
	for j := 0; j <= len(rb); j++ {
		sb.WriteString("---|")
	}
	sb.WriteString("\n")
	// Data rows.
	for i := 0; i <= len(ra); i++ {
		if i == 0 {
			sb.WriteString("| **ε** |")
		} else {
			sb.WriteString("| **`")
			sb.WriteString(string(ra[i-1]))
			sb.WriteString("`** |")
		}
		for j := 0; j <= len(rb); j++ {
			sb.WriteString(" ")
			sb.WriteString(strconv.Itoa(d[i][j]))
			sb.WriteString(" |")
		}
		sb.WriteString("\n")
	}
	return sb.String()
}

// Render implements the gnoweb view.
//
//   - "" or "/"            : explanation + examples.
//   - "/<a>/<b>"           : distance between a and b, with the DP table.
func Render(path string) string {
	path = strings.TrimPrefix(path, "/")
	if path == "" {
		return renderHome()
	}

	parts := strings.SplitN(path, "/", 2)
	if len(parts) != 2 {
		var sb strings.Builder
		sb.WriteString("# Levenshtein\n\n")
		sb.WriteString("Provide two words as `/<a>/<b>`, e.g. [`/kitten/sitting`](/r/moul/x/daily/levenshtein:kitten/sitting).\n\n")
		sb.WriteString("[← back](/r/moul/x/daily/levenshtein)\n")
		return sb.String()
	}

	a := parts[0]
	b := parts[1]
	dist := Distance(a, b)
	sim := Similarity(a, b)

	var sb strings.Builder
	sb.WriteString("# Levenshtein distance\n\n")
	sb.WriteString("Transforming **`")
	sb.WriteString(a)
	sb.WriteString("`** → **`")
	sb.WriteString(b)
	sb.WriteString("`**\n\n")
	sb.WriteString("- **Edit distance:** `")
	sb.WriteString(strconv.Itoa(dist))
	sb.WriteString("` single-character edits (insert / delete / substitute)\n")
	sb.WriteString("- **Similarity:** `")
	sb.WriteString(strconv.Itoa(sim))
	sb.WriteString("%`\n\n")

	sb.WriteString("## DP table\n\n")
	sb.WriteString("Each cell `d[i][j]` is the distance between the first *i* runes of `")
	sb.WriteString(a)
	sb.WriteString("` and the first *j* runes of `")
	sb.WriteString(b)
	sb.WriteString("`. The bottom-right cell is the answer.\n\n")
	sb.WriteString(renderTable(a, b))
	sb.WriteString("\n[← back](/r/moul/x/daily/levenshtein)\n")
	return sb.String()
}

func renderHome() string {
	var sb strings.Builder
	sb.WriteString("# Levenshtein edit distance\n\n")
	sb.WriteString("The **Levenshtein distance** between two strings is the minimum number of ")
	sb.WriteString("single-character edits — *insertions*, *deletions*, or *substitutions* — ")
	sb.WriteString("needed to turn one string into the other. This realm reimplements the classic ")
	sb.WriteString("dynamic-programming algorithm (à la Go's `agext/levenshtein`) fully rune-aware and on-chain.\n\n")

	sb.WriteString("## Try it\n\n")
	sb.WriteString("Append two words as `/<a>/<b>`:\n\n")
	examples := [][2]string{
		{"kitten", "sitting"},
		{"flaw", "lawn"},
		{"sunday", "saturday"},
		{"gno", "gnoland"},
	}
	for _, ex := range examples {
		a, b := ex[0], ex[1]
		d := Distance(a, b)
		sb.WriteString("- [`/")
		sb.WriteString(a)
		sb.WriteString("/")
		sb.WriteString(b)
		sb.WriteString("`](/r/moul/x/daily/levenshtein:")
		sb.WriteString(a)
		sb.WriteString("/")
		sb.WriteString(b)
		sb.WriteString(") → distance **")
		sb.WriteString(strconv.Itoa(d))
		sb.WriteString("**\n")
	}

	sb.WriteString("\n## The classic example\n\n")
	sb.WriteString("`kitten` → `sitting` = **3**:\n\n")
	sb.WriteString("1. `kitten` → `sitten` (substitute *k* → *s*)\n")
	sb.WriteString("2. `sitten` → `sittin` (substitute *e* → *i*)\n")
	sb.WriteString("3. `sittin` → `sitting` (insert *g* at the end)\n\n")

	sb.WriteString("## API\n\n")
	sb.WriteString("- `Distance(a, b string) int` — the edit distance.\n")
	sb.WriteString("- `Matrix(a, b string) [][]int` — the full DP matrix.\n")
	sb.WriteString("- `Similarity(a, b string) int` — a 0..100 similarity percentage.\n")
	return sb.String()
}
