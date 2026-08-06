// Package rot13 ports Go's classic ROT13 example — the one used to teach
// strings.Map and io.Reader in the standard library docs — to gno as a reusable
// pure package. The core is a pure letter-rotation cipher over ASCII: ROT13
// shifts each letter 13 places, which (since the alphabet has 26 letters)
// makes ROT13 its own inverse. Caesar generalizes it to any shift.
//
// Everything here is pure strings/unicode logic: no state, no randomness,
// no clock.
//
// A live demo of this package is at
// [r/moul/x/daily/rot13demo](/r/moul/x/daily/rot13demo/v1).
package rot13

import "strings"

// Rot13 applies the ROT13 substitution cipher, rotating ASCII letters by 13
// and leaving every other byte untouched. Because 13 is half of 26,
// Rot13(Rot13(s)) == s — the cipher is its own inverse. This mirrors the
// canonical strings.Map example from the Go docs.
func Rot13(s string) string {
	return strings.Map(rot13Rune, s)
}

// rot13Rune is the mapping function handed to strings.Map — the heart of the
// classic example.
func rot13Rune(r rune) rune {
	switch {
	case r >= 'a' && r <= 'z':
		return 'a' + (r-'a'+13)%26
	case r >= 'A' && r <= 'Z':
		return 'A' + (r-'A'+13)%26
	}
	return r
}

// Caesar generalizes ROT13 to an arbitrary shift. Negative and large shifts
// are normalized into [0,26). Only ASCII letters move; anything else passes
// through unchanged. Caesar(s, 13) is exactly Rot13(s).
func Caesar(s string, shift int) string {
	sh := rune(((shift % 26) + 26) % 26)
	return strings.Map(func(r rune) rune {
		switch {
		case r >= 'a' && r <= 'z':
			return 'a' + (r-'a'+sh)%26
		case r >= 'A' && r <= 'Z':
			return 'A' + (r-'A'+sh)%26
		}
		return r
	}, s)
}
