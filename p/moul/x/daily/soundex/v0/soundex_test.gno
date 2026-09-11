package soundex

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// The canonical examples, including the three that catch a naive
// implementation: Pfister, Tymczak and Ashcraft.
func TestEncodeCanonical(t *testing.T) {
	cases := []struct{ in, want string }{
		{"Robert", "R163"},
		{"Rupert", "R163"},
		{"Rubin", "R150"},
		{"Ashcraft", "A261"}, // 'h' is transparent: s and c collapse
		{"Ashcroft", "A261"},
		{"Tymczak", "T522"}, // vowel separates, so 2 repeats
		{"Pfister", "P236"}, // first letter's code suppresses the f
		{"Honeyman", "H555"},
		{"Jackson", "J250"},
		{"Washington", "W252"},
		{"Lee", "L000"},
		{"Gutierrez", "G362"},
	}
	for _, c := range cases {
		uassert.Equal(t, c.want, Encode(c.in))
	}
}

// The first letter keeps its own code for suppression purposes — the rule most
// often missed. Without it "Pfister" would come out P123.
func TestFirstLetterSuppresses(t *testing.T) {
	uassert.Equal(t, "P236", Encode("Pfister"))
	uassert.Equal(t, "B000", Encode("Bb"))
}

// 'h'/'w' are transparent; vowels are not.
func TestTransparentHW(t *testing.T) {
	uassert.Equal(t, Encode("Ashcraft"), Encode("Ascraft"))
	// a vowel between the same two codes does NOT collapse them
	uassert.Equal(t, "T522", Encode("Tymczak"))
}

func TestCaseAndPunctuationIgnored(t *testing.T) {
	uassert.Equal(t, Encode("OBrien"), Encode("O'Brien"))
	uassert.Equal(t, Encode("robert"), Encode("ROBERT"))
	uassert.Equal(t, "R163", Encode("  Robert!  "))
}

func TestNoLetters(t *testing.T) {
	uassert.Equal(t, "", Encode(""))
	uassert.Equal(t, "", Encode("12345"))
	uassert.Equal(t, "", Encode("!!!"))
}

// Two inputs with no letters are not "the same name".
func TestMatch(t *testing.T) {
	uassert.True(t, Match("Robert", "Rupert"))
	uassert.False(t, Match("Robert", "Rubin"))
	uassert.False(t, Match("", ""))
	uassert.False(t, Match("123", "456"))
}

// Always exactly four characters, padded with zeros.
func TestAlwaysFourChars(t *testing.T) {
	for _, s := range []string{"A", "Lee", "Robert", "Washington", "Supercalifragilistic"} {
		uassert.Equal(t, 4, len(Encode(s)))
	}
}

func TestEncodeAllAndNormalize(t *testing.T) {
	got := EncodeAll([]string{"Robert", "Lee"})
	uassert.Equal(t, 2, len(got))
	uassert.Equal(t, "R163", got[0])
	uassert.Equal(t, "L000", got[1])
	uassert.Equal(t, "OBRIEN", Normalize("O'Brien"))
}
