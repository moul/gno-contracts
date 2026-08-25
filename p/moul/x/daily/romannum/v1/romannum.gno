// Package romannum is a pure port of the classic Roman-numeral converter kata:
// ToRoman / FromRoman, valid for 1..3999. Deterministic — no time, randomness
// or I/O — and free of any realm coupling, so it is reusable as a library.
//
// A live demo of this package (an interactive integer↔Roman converter) is at
// [r/moul/x/daily/romannumdemo](/r/moul/x/daily/romannumdemo/v1).
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

// parseRoman is the pure, panic-free core used by FromRoman.
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
