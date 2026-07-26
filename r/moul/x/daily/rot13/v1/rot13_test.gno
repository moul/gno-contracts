package rot13

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestRot13(t *testing.T) {
	cases := []struct {
		in, want string
	}{
		{"", ""},
		{"Hello", "Uryyb"},
		{"Uryyb", "Hello"},                 // decode
		{"abcxyz", "nopklm"},               // wraps within lowercase
		{"ABCXYZ", "NOPKLM"},               // wraps within uppercase
		{"Hello, Gno! 123", "Uryyb, Tab! 123"}, // punctuation & digits untouched
	}
	for _, c := range cases {
		got := Rot13(c.in)
		uassert.Equal(t, c.want, got, "Rot13(%q)", c.in)
	}
}

func TestRot13IsItsOwnInverse(t *testing.T) {
	inputs := []string{"", "Hello, Gno!", "The quick brown fox", "MixedCASE 42!"}
	for _, in := range inputs {
		uassert.Equal(t, in, Rot13(Rot13(in)), "Rot13(Rot13(%q)) should round-trip", in)
	}
}

func TestCaesar(t *testing.T) {
	cases := []struct {
		in    string
		shift int
		want  string
	}{
		{"abc", 1, "bcd"},
		{"xyz", 3, "abc"},          // wraps around the end
		{"ABC", 25, "ZAB"},         // large shift, uppercase
		{"Hello", 0, "Hello"},      // no-op
		{"Hello", 26, "Hello"},     // full rotation
		{"bcd", -1, "abc"},         // negative shift
		{"a-b c!", 1, "b-c d!"},    // non-letters untouched
		{"Hello, Gno!", 13, "Uryyb, Tab!"}, // shift 13 == ROT13
	}
	for _, c := range cases {
		got := Caesar(c.in, c.shift)
		uassert.Equal(t, c.want, got, "Caesar(%q, %d)", c.in, c.shift)
	}
}

func TestCaesarEqualsRot13At13(t *testing.T) {
	inputs := []string{"Hello, Gno!", "The quick brown fox jumps"}
	for _, in := range inputs {
		uassert.Equal(t, Rot13(in), Caesar(in, 13), "Caesar(%q,13) should equal Rot13", in)
	}
}

func TestPercentDecode(t *testing.T) {
	uassert.Equal(t, "attack at dawn", percentDecode("attack%20at%20dawn"))
	uassert.Equal(t, "a b", percentDecode("a+b"))
	uassert.Equal(t, "100%", percentDecode("100%"))     // trailing bare percent kept
	uassert.Equal(t, "%zz", percentDecode("%zz"))       // invalid escape kept verbatim
	uassert.Equal(t, "Hello!", percentDecode("Hello%21"))
}
