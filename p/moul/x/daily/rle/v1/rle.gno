// Package rle implements run-length encoding as a pure, reusable package: runs
// of a repeated byte collapse to a count and the byte.
//
// The encoding is `<count><char>` with counts in decimal, e.g. "aaabbc" →
// "3a2b1c". Every run is emitted with its count, including runs of one — a
// uniform grammar is cheaper to decode and impossible to get subtly wrong,
// at the cost of expanding data that has no runs at all. RLE is a *win only on
// runny data*; Encode can legitimately produce output longer than its input,
// and the demo shows exactly that case rather than hiding it.
//
// Digits cannot appear in the input, since they would be indistinguishable from
// a count on the way back; Encode rejects them rather than round-tripping wrong.
//
// A live demo of this package is at
// [r/moul/x/daily/rledemo](/r/moul/x/daily/rledemo/v1).
package rle

import (
	"errors"
	"strconv"
	"strings"
)

// MaxLen bounds input so encode/decode gas stays predictable.
const MaxLen = 4096

var (
	// ErrTooLong is returned when input exceeds MaxLen.
	ErrTooLong = errors.New("rle: input too long")
	// ErrDigit is returned when input contains a digit, which would be
	// ambiguous with a run count.
	ErrDigit = errors.New("rle: input must not contain digits")
	// ErrMalformed is returned when decoding input that is not <count><char>.
	ErrMalformed = errors.New("rle: malformed input")
)

// Encode collapses runs of repeated bytes into <count><char> pairs.
func Encode(s string) (string, error) {
	if len(s) > MaxLen {
		return "", ErrTooLong
	}
	for i := 0; i < len(s); i++ {
		if s[i] >= '0' && s[i] <= '9' {
			return "", ErrDigit
		}
	}
	if s == "" {
		return "", nil
	}
	var b strings.Builder
	run := 1
	for i := 1; i <= len(s); i++ {
		if i < len(s) && s[i] == s[i-1] {
			run++
			continue
		}
		b.WriteString(strconv.Itoa(run))
		b.WriteByte(s[i-1])
		run = 1
	}
	return b.String(), nil
}

// Decode expands <count><char> pairs back into the original string.
func Decode(s string) (string, error) {
	if len(s) > MaxLen {
		return "", ErrTooLong
	}
	var b strings.Builder
	i := 0
	for i < len(s) {
		j := i
		for j < len(s) && s[j] >= '0' && s[j] <= '9' {
			j++
		}
		if j == i || j == len(s) { // no count, or a count with no character
			return "", ErrMalformed
		}
		n, err := strconv.Atoi(s[i:j])
		if err != nil || n <= 0 {
			return "", ErrMalformed
		}
		if b.Len()+n > MaxLen {
			return "", ErrTooLong // a short input can decode to an enormous one
		}
		b.WriteString(strings.Repeat(string(s[j]), n))
		i = j + 1
	}
	return b.String(), nil
}

// Ratio returns len(encoded)/len(original) as a percentage, rounded down.
// Over 100 means the encoding made the data BIGGER, which is the honest
// outcome for input without runs.
func Ratio(original, encoded string) int {
	if len(original) == 0 {
		return 0
	}
	return len(encoded) * 100 / len(original)
}
