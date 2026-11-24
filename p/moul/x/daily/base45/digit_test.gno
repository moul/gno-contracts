package base45

import (
	"strings"
	"testing"
)

// TestDigitMatchesAlphabet pins the arithmetic fast path of digit against the
// Alphabet it replaces a scan of, over every byte: each character maps to its
// index, and every byte outside the alphabet (lowercase included) is corrupt.
func TestDigitMatchesAlphabet(t *testing.T) {
	for c := 0; c < 256; c++ {
		want := strings.IndexByte(Alphabet, byte(c))
		got, err := digit(byte(c))
		if want < 0 {
			if err != ErrCorrupt {
				t.Errorf("digit(%d) = %d, %v; want ErrCorrupt", c, got, err)
			}
			continue
		}
		if err != nil || got != want {
			t.Errorf("digit(%d) = %d, %v; want %d", c, got, err, want)
		}
	}
}
