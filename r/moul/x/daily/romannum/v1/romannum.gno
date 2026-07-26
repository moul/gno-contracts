// Package romannum is an on-chain port of the classic Roman-numeral converter
// kata: ToRoman/FromRoman. Pure and deterministic — no time, randomness or I/O.
package romannum

import (
	"strconv"
	"strings"
)

// romanUnits is the greedy subtractive-notation table, largest value first.
var romanUnits = []struct {
	val int
	sym string
}{
	{1000, "M"}, {900, "CM"}, {500, "D"}, {400, "CD"},
	{100, "C"}, {90, "XC"}, {50, "L"}, {40, "XL"},
	{10, "X"}, {9, "IX"}, {5, "V"}, {4, "IV"}, {1, "I"},
}

// ToRoman renders an integer in 1..3999 as a Roman numeral.
// It panics if n is out of range.
func ToRoman(n int) string {
	if n < 1 || n > 3999 {
		panic("romannum: out of range (want 1..3999): " + strconv.Itoa(n))
	}
	var b strings.Builder
	for _, u := range romanUnits {
		for n >= u.val {
			b.WriteString(u.sym)
			n -= u.val
		}
	}
	return b.String()
}

// FromRoman parses a Roman numeral back to an integer.
// It panics on any malformed input (e.g. "IIII", "IC", "VV").
func FromRoman(s string) int {
	n, ok := parseRoman(s)
	if !ok {
		panic("romannum: invalid roman numeral: " + s)
	}
	return n
}

// charVal maps a single Roman digit to its value, or 0 if unknown.
func charVal(c byte) int {
	switch c {
	case 'I':
		return 1
	case 'V':
		return 5
	case 'X':
		return 10
	case 'L':
		return 50
	case 'C':
		return 100
	case 'D':
		return 500
	case 'M':
		return 1000
	}
	return 0
}

// parseRoman is the pure, panic-free core used by FromRoman and Render.
// It returns (value, true) only for a canonical numeral: it accepts input
// iff ToRoman(value) reproduces it exactly, which rejects malformed forms.
func parseRoman(s string) (int, bool) {
	s = strings.ToUpper(strings.TrimSpace(s))
	if s == "" {
		return 0, false
	}
	total, prev := 0, 0
	for i := len(s) - 1; i >= 0; i-- {
		v := charVal(s[i])
		if v == 0 {
			return 0, false
		}
		if v < prev {
			total -= v
		} else {
			total += v
			prev = v
		}
	}
	if total < 1 || total > 3999 || ToRoman(total) != s {
		return 0, false
	}
	return total, true
}

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
	b.WriteString("# " + strconv.Itoa(n) + " → " + ToRoman(n) + "\n\n")
	b.WriteString("| decimal | roman |\n|---:|:---|\n")
	b.WriteString("| " + strconv.Itoa(n) + " | **" + ToRoman(n) + "** |\n\n")
	if n > 1 {
		b.WriteString("[« " + strconv.Itoa(n-1) + "](/r/moul/x/daily/romannum/v1:" +
			strconv.Itoa(n-1) + ") · ")
	}
	if n < 3999 {
		b.WriteString("[" + strconv.Itoa(n+1) + " »](/r/moul/x/daily/romannum/v1:" +
			strconv.Itoa(n+1) + ")")
	}
	b.WriteString("\n\n" + usage())
	return b.String()
}

func renderFromRoman(arg string) string {
	arg = strings.TrimSpace(arg)
	n, ok := parseRoman(arg)
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

func renderTable() string {
	var b strings.Builder
	b.WriteString("# Roman numeral converter\n\n")
	b.WriteString("A tiny on-chain port of the classic `ToRoman` / `FromRoman` kata. ")
	b.WriteString("Pure and deterministic.\n\n")
	b.WriteString("## Examples\n\n")
	b.WriteString("| decimal | roman |\n|---:|:---|\n")
	for _, n := range examples {
		b.WriteString("| [" + strconv.Itoa(n) + "](/r/moul/x/daily/romannum/v1:" +
			strconv.Itoa(n) + ") | " + ToRoman(n) + " |\n")
	}
	b.WriteString("\n" + usage())
	return b.String()
}

func usage() string {
	return "## Try it\n\n" +
		"- `:/<n>` — integer → Roman, e.g. `:/2024` → " + ToRoman(2024) + "\n" +
		"- `:/r/<roman>` — Roman → integer, e.g. `:/r/MMXXIV` → 2024\n"
}
