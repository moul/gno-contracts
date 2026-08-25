// Package luhn implements the Luhn mod-10 checksum (Hans Peter Luhn, 1954) as
// a pure, reusable package: the check used by credit-card numbers, IMEIs and
// many national ID schemes to catch typos and single-digit transpositions.
//
// It is a *checksum*, not a security primitive: it detects every single-digit
// error and almost every adjacent transposition, but it is trivial to forge and
// says nothing about whether an identifier actually exists. Never use it to
// authorize anything on-chain.
//
// No clocks, no randomness, no chain imports — same input, same output.
//
// A live demo of this package is at
// [r/moul/x/daily/luhndemo](/r/moul/x/daily/luhndemo/v1).
package luhn

import (
	"strings"
)

// MaxLen bounds an input so validation gas stays predictable.
const MaxLen = 64

// Valid reports whether s carries a correct Luhn check digit.
//
// Spaces and hyphens are ignored, so "4539 1488 0343 6467" and
// "4539-1488-0343-6467" both work. Any other non-digit makes it false, as does
// an empty/1-digit input or one longer than MaxLen. A string of all zeros is
// technically Luhn-valid and is accepted — reject it in the caller if your
// domain needs to.
func Valid(s string) bool {
	digits, ok := clean(s)
	if !ok || len(digits) < 2 {
		return false
	}
	return sum(digits)%10 == 0
}

// CheckDigit returns the digit that must be appended to payload to make the
// whole string Luhn-valid, and whether the payload was usable.
func CheckDigit(payload string) (int, bool) {
	digits, ok := clean(payload)
	if !ok || len(digits) == 0 {
		return 0, false
	}
	// The check digit sits in the "doubled" position of the final number, so
	// compute the sum as if a 0 had already been appended.
	total := sum(append(digits, 0))
	return (10 - total%10) % 10, true
}

// Append returns payload with its Luhn check digit appended (digits only,
// separators stripped), and whether the payload was usable.
func Append(payload string) (string, bool) {
	d, ok := CheckDigit(payload)
	if !ok {
		return "", false
	}
	digits, _ := clean(payload)
	var b strings.Builder
	for _, x := range digits {
		b.WriteByte(byte('0' + x))
	}
	b.WriteByte(byte('0' + d))
	return b.String(), true
}

// clean turns s into its digit values, ignoring spaces and hyphens. ok is false
// if any other character appears or the input exceeds MaxLen.
func clean(s string) ([]int, bool) {
	if len(s) > MaxLen {
		return nil, false
	}
	digits := make([]int, 0, len(s))
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case c >= '0' && c <= '9':
			digits = append(digits, int(c-'0'))
		case c == ' ' || c == '-':
			// separator: ignore
		default:
			return nil, false
		}
	}
	return digits, true
}

// sum computes the Luhn total: walking right to left, every second digit is
// doubled, and a double of 10 or more has 9 subtracted (equivalent to adding
// its two decimal digits).
func sum(digits []int) int {
	total := 0
	double := false
	for i := len(digits) - 1; i >= 0; i-- {
		d := digits[i]
		if double {
			d *= 2
			if d > 9 {
				d -= 9
			}
		}
		total += d
		double = !double
	}
	return total
}
