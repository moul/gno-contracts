// Package luhndemo is a small gnoweb demo of the Luhn mod-10 checksum provided
// by the [p/moul/x/daily/luhn](/p/moul/x/daily/luhn/v1) library: put a number
// in the path and it tells you whether the check digit is right, and what it
// should have been.
//
// It contains no checksum logic of its own — validation, the check digit and
// the separator handling all come from the library. Read-only and stateless, so
// Render is fully deterministic.
package luhndemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/x/daily/luhn/v1"
)

// samples are shown on the root page: a valid number, a typo'd one, and a
// transposition — the two error classes Luhn is designed to catch.
var samples = []struct {
	number string
	note   string
}{
	{"79927398713", "the textbook example"},
	{"79927398710", "same number, wrong check digit"},
	{"4539148803436467", "a test card number"},
	{"4539148803436647", "same card, two digits swapped"},
}

// Render renders the checker for gnoweb.
//
//	Render("")        / Render("/") -> usage + worked samples
//	Render("/<digits>")             -> verdict for that number
func Render(path string) string {
	in := parseInput(path)

	var b strings.Builder
	b.WriteString("# Luhn Checksum\n\n")
	b.WriteString("The mod-10 check behind card numbers and IMEIs, demoing the ")
	b.WriteString("[`p/moul/x/daily/luhn`](/p/moul/x/daily/luhn/v1) library.\n\n")

	if in == "" {
		b.WriteString("Append a number to the path to check it — spaces and hyphens are ignored.\n\n")
		b.WriteString("## Samples\n\n")
		b.WriteString("| number | valid? | note |\n|---|---|---|\n")
		for _, s := range samples {
			b.WriteString("| `")
			b.WriteString(s.number)
			b.WriteString("` | ")
			b.WriteString(verdict(luhn.Valid(s.number)))
			b.WriteString(" | ")
			b.WriteString(s.note)
			b.WriteString(" |\n")
		}
		b.WriteString("\n> Luhn is a **typo check, not a security check**: it catches every ")
		b.WriteString("single-digit error and nearly every swap of adjacent digits, but ")
		b.WriteString("anyone can compute a valid number. Never authorize anything with it.\n")
		return b.String()
	}

	b.WriteString("## `")
	b.WriteString(in)
	b.WriteString("`\n\n")

	if luhn.Valid(in) {
		b.WriteString("**Valid** — the check digit matches.\n")
		return b.String()
	}

	b.WriteString("**Not valid.**\n\n")
	// Offer the fix: treat everything but the last digit as the payload.
	if payload, ok := trimLast(in); ok {
		if d, ok2 := luhn.CheckDigit(payload); ok2 {
			b.WriteString("Keeping the leading digits, the check digit should be **")
			b.WriteString(strconv.Itoa(d))
			b.WriteString("**")
			if fixed, ok3 := luhn.Append(payload); ok3 {
				b.WriteString(" — i.e. `")
				b.WriteString(fixed)
				b.WriteString("`")
			}
			b.WriteString(".\n")
			return b.String()
		}
	}
	b.WriteString("It has no usable digits to check.\n")
	return b.String()
}

// parseInput extracts the first path segment.
func parseInput(path string) string {
	s := strings.TrimSpace(path)
	s = strings.TrimPrefix(s, "/")
	if i := strings.IndexByte(s, '/'); i >= 0 {
		s = s[:i]
	}
	return s
}

// trimLast drops the final digit, ignoring separators, to recover the payload.
func trimLast(s string) (string, bool) {
	for i := len(s) - 1; i >= 0; i-- {
		if s[i] >= '0' && s[i] <= '9' {
			return s[:i], true
		}
	}
	return "", false
}

func verdict(ok bool) string {
	if ok {
		return "✅ valid"
	}
	return "❌ invalid"
}
