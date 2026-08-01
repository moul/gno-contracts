// Package levenshteindemo is a small gnoweb demo of the Levenshtein edit-distance
// library provided by [p/moul/x/daily/levenshtein](/p/moul/x/daily/levenshtein/v1):
// it renders an explanation, worked examples, and an interactive distance
// calculator with the full dynamic-programming table.
//
// It contains no distance logic of its own — everything comes from
// `levenshtein.Distance`, `levenshtein.Matrix` and `levenshtein.Similarity`.
package levenshteindemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/x/daily/levenshtein/v1"
)

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
		sb.WriteString("Provide two words as `/<a>/<b>`, e.g. [`/kitten/sitting`](/r/moul/x/daily/levenshteindemo/v1:kitten/sitting).\n\n")
		sb.WriteString("[← back](/r/moul/x/daily/levenshteindemo/v1)\n")
		return sb.String()
	}

	a := parts[0]
	b := parts[1]
	dist := levenshtein.Distance(a, b)
	sim := levenshtein.Similarity(a, b)

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
	sb.WriteString("\n[← back](/r/moul/x/daily/levenshteindemo/v1)\n")
	return sb.String()
}

func renderHome() string {
	var sb strings.Builder
	sb.WriteString("# Levenshtein edit distance\n\n")
	sb.WriteString("Demo of the [`p/moul/x/daily/levenshtein`](/p/moul/x/daily/levenshtein/v1) library. ")
	sb.WriteString("The **Levenshtein distance** between two strings is the minimum number of ")
	sb.WriteString("single-character edits — *insertions*, *deletions*, or *substitutions* — ")
	sb.WriteString("needed to turn one string into the other. The library implements the classic ")
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
		d := levenshtein.Distance(a, b)
		sb.WriteString("- [`/")
		sb.WriteString(a)
		sb.WriteString("/")
		sb.WriteString(b)
		sb.WriteString("`](/r/moul/x/daily/levenshteindemo/v1:")
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

// renderTable formats the DP matrix as a Markdown table with a and b as headers.
func renderTable(a, b string) string {
	ra := []rune(a)
	rb := []rune(b)
	d := levenshtein.Matrix(a, b)

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
