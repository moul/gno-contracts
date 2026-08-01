// Package romannumdemo is a small gnoweb demo of the Roman-numeral converter
// provided by the [p/moul/x/daily/romannum](/p/moul/x/daily/romannum/v1)
// library: it renders a table of worked examples and interactive
// integer→Roman and Roman→integer conversions.
//
// It contains no conversion logic of its own — everything comes from
// romannum.ToRoman and romannum.FromRoman.
package romannumdemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/x/daily/romannum/v1"
)

// examples are the classic milestones shown by the root Render.
var examples = []int{1, 4, 9, 14, 40, 49, 90, 400, 900, 1994, 2024, 3888, 3999}

// Render drives gnoweb:
//   - ""        or "/"          → a table of example conversions
//   - "/<n>"                    → integer → Roman
//   - "/r/<roman>"              → Roman → integer
func Render(path string) string {
	arg := strings.Trim(strings.TrimSpace(path), "/")

	switch {
	case arg == "":
		return renderTable()
	case strings.HasPrefix(strings.ToLower(arg), "r/"):
		return renderFromRoman(arg[2:])
	default:
		return renderToRoman(arg)
	}
}

func renderToRoman(arg string) string {
	n, err := strconv.Atoi(strings.TrimSpace(arg))
	if err != nil {
		return "# Roman numeral converter\n\nCould not parse `" + arg +
			"` as an integer.\n\n" + usage()
	}
	if n < 1 || n > 3999 {
		return "# Roman numeral converter\n\n`" + strconv.Itoa(n) +
			"` is out of range — Roman numerals here cover **1..3999**.\n\n" + usage()
	}
	var b strings.Builder
	b.WriteString("# " + strconv.Itoa(n) + " → " + romannum.ToRoman(n) + "\n\n")
	b.WriteString("| decimal | roman |\n|---:|:---|\n")
	b.WriteString("| " + strconv.Itoa(n) + " | **" + romannum.ToRoman(n) + "** |\n\n")
	if n > 1 {
		b.WriteString("[« " + strconv.Itoa(n-1) + "](/r/moul/x/daily/romannumdemo/v1:" +
			strconv.Itoa(n-1) + ") · ")
	}
	if n < 3999 {
		b.WriteString("[" + strconv.Itoa(n+1) + " »](/r/moul/x/daily/romannumdemo/v1:" +
			strconv.Itoa(n+1) + ")")
	}
	b.WriteString("\n\n" + usage())
	return b.String()
}

func renderFromRoman(arg string) string {
	arg = strings.TrimSpace(arg)
	n, ok := tryFromRoman(arg)
	if !ok {
		return "# Roman numeral converter\n\n`" + arg +
			"` is not a valid Roman numeral (1..3999).\n\n" + usage()
	}
	up := strings.ToUpper(arg)
	var b strings.Builder
	b.WriteString("# " + up + " → " + strconv.Itoa(n) + "\n\n")
	b.WriteString("| roman | decimal |\n|:---|---:|\n")
	b.WriteString("| **" + up + "** | " + strconv.Itoa(n) + " |\n\n")
	b.WriteString(usage())
	return b.String()
}

// tryFromRoman wraps the panic-on-invalid romannum.FromRoman in a panic-free
// (value, ok) shape, so the demo can report a friendly error for bad input.
func tryFromRoman(s string) (n int, ok bool) {
	defer func() {
		if recover() != nil {
			n, ok = 0, false
		}
	}()
	return romannum.FromRoman(s), true
}

func renderTable() string {
	var b strings.Builder
	b.WriteString("# Roman numeral converter\n\n")
	b.WriteString("A tiny demo of the [`p/moul/x/daily/romannum`](/p/moul/x/daily/romannum/v1) ")
	b.WriteString("library — the classic `ToRoman` / `FromRoman` kata. ")
	b.WriteString("Pure and deterministic.\n\n")
	b.WriteString("## Examples\n\n")
	b.WriteString("| decimal | roman |\n|---:|:---|\n")
	for _, n := range examples {
		b.WriteString("| [" + strconv.Itoa(n) + "](/r/moul/x/daily/romannumdemo/v1:" +
			strconv.Itoa(n) + ") | " + romannum.ToRoman(n) + " |\n")
	}
	b.WriteString("\n" + usage())
	return b.String()
}

func usage() string {
	return "## Try it\n\n" +
		"- `:/<n>` — integer → Roman, e.g. `:/2024` → " + romannum.ToRoman(2024) + "\n" +
		"- `:/r/<roman>` — Roman → integer, e.g. `:/r/MMXXIV` → 2024\n"
}
