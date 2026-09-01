// Package soundex implements the Soundex phonetic algorithm as a pure,
// reusable package: names that sound alike in English encode to the same
// four-character key, so "Robert" and "Rupert" both give R163.
//
// This is the 1918 Russell/Odell algorithm as used by the US census, with the
// rules that are usually got wrong implemented explicitly:
//
//   - the first letter is kept as-is and its digit still suppresses a
//     following consonant of the same code ("Pfister" → P236, not P123);
//   - 'h' and 'w' are TRANSPARENT: consonants either side of them are treated
//     as adjacent ("Ashcraft" → A261, not A226);
//   - vowels are not transparent — they separate, so a repeated code after a
//     vowel is emitted again ("Tymczak" → T522).
//
// Soundex is English-centric and lossy by design: it is a *blocking* key for
// finding candidates, never a proof that two names match.
//
// A live demo of this package is at
// [r/moul/x/daily/soundexdemo](/r/moul/x/daily/soundexdemo/v1).
package soundex

import "strings"

// code returns the Soundex digit for a letter, or 0 for vowels and h/w/y.
func code(c byte) byte {
	switch c {
	case 'B', 'F', 'P', 'V':
		return '1'
	case 'C', 'G', 'J', 'K', 'Q', 'S', 'X', 'Z':
		return '2'
	case 'D', 'T':
		return '3'
	case 'L':
		return '4'
	case 'M', 'N':
		return '5'
	case 'R':
		return '6'
	}
	return 0
}

// upper returns c upper-cased if it is an ASCII letter, else 0.
func upper(c byte) byte {
	if c >= 'a' && c <= 'z' {
		c -= 32
	}
	if c >= 'A' && c <= 'Z' {
		return c
	}
	return 0
}

// Encode returns the four-character Soundex key for s, or "" when s contains
// no ASCII letters. Non-letters are ignored, so "O'Brien" and "OBrien" agree.
func Encode(s string) string {
	// keep letters only
	letters := make([]byte, 0, len(s))
	for i := 0; i < len(s); i++ {
		if c := upper(s[i]); c != 0 {
			letters = append(letters, c)
		}
	}
	if len(letters) == 0 {
		return ""
	}

	out := []byte{letters[0]}
	prev := code(letters[0]) // the first letter's own code still suppresses

	for i := 1; i < len(letters) && len(out) < 4; i++ {
		c := letters[i]
		d := code(c)
		switch {
		case d == 0:
			// 'h' and 'w' are transparent: leave prev alone so the consonants
			// either side are treated as adjacent. Vowels (and 'y') separate,
			// so they reset prev and allow the same code to repeat.
			if c != 'H' && c != 'W' {
				prev = 0
			}
		case d != prev:
			out = append(out, d)
			prev = d
		default:
			// same code as the previous consonant, and not separated by a
			// vowel: collapsed.
		}
	}
	for len(out) < 4 {
		out = append(out, '0')
	}
	return string(out)
}

// Match reports whether two strings share a Soundex key. Empty keys never
// match, so two inputs with no letters are not "the same name".
func Match(a, b string) bool {
	ka, kb := Encode(a), Encode(b)
	return ka != "" && ka == kb
}

// EncodeAll returns the keys for each input, in order.
func EncodeAll(names []string) []string {
	out := make([]string, 0, len(names))
	for _, n := range names {
		out = append(out, Encode(n))
	}
	return out
}

// Normalize upper-cases and strips non-letters — the input Encode actually
// sees. Exposed so callers can show their work.
func Normalize(s string) string {
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		if c := upper(s[i]); c != 0 {
			b.WriteByte(c)
		}
	}
	return b.String()
}
