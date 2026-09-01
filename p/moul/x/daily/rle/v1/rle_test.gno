package rle

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestEncode(t *testing.T) {
	cases := []struct{ in, want string }{
		{"", ""},
		{"a", "1a"},
		{"aaa", "3a"},
		{"aaabbc", "3a2b1c"},
		{"abc", "1a1b1c"},
		{"aabbaa", "2a2b2a"}, // runs, not totals
	}
	for _, c := range cases {
		got, err := Encode(c.in)
		uassert.NoError(t, err)
		uassert.Equal(t, c.want, got)
	}
}

func TestDecode(t *testing.T) {
	cases := []struct{ in, want string }{
		{"", ""},
		{"3a", "aaa"},
		{"3a2b1c", "aaabbc"},
		{"12x", strings.Repeat("x", 12)}, // multi-digit counts
	}
	for _, c := range cases {
		got, err := Decode(c.in)
		uassert.NoError(t, err)
		uassert.Equal(t, c.want, got)
	}
}

// The property that matters: decode(encode(s)) == s.
func TestRoundTrip(t *testing.T) {
	for _, s := range []string{"a", "aaa", "aaabbc", "abcdef", "zzzzzzzzzzzz", "ab"} {
		enc, err := Encode(s)
		uassert.NoError(t, err)
		dec, err2 := Decode(enc)
		uassert.NoError(t, err2)
		uassert.Equal(t, s, dec)
	}
}

// Digits would be ambiguous with a run count, so they are refused up front.
func TestEncodeRejectsDigits(t *testing.T) {
	_, err := Encode("ab3c")
	uassert.ErrorIs(t, err, ErrDigit)
}

func TestDecodeMalformed(t *testing.T) {
	for _, s := range []string{"a", "abc", "3", "3a2", "0a"} {
		_, err := Decode(s)
		uassert.Error(t, err)
	}
}

// A short encoded input must not be able to blow up memory on decode.
func TestDecodeExpansionIsBounded(t *testing.T) {
	_, err := Decode("999999x")
	uassert.ErrorIs(t, err, ErrTooLong)
}

func TestEncodeTooLong(t *testing.T) {
	_, err := Encode(strings.Repeat("a", MaxLen+1))
	uassert.ErrorIs(t, err, ErrTooLong)
}

// RLE is a win only on runny data — say so rather than hide it.
func TestRatioCanExceed100(t *testing.T) {
	enc, _ := Encode("abcdef")
	uassert.Equal(t, "1a1b1c1d1e1f", enc)
	uassert.Equal(t, 200, Ratio("abcdef", enc)) // twice the size!
	enc2, _ := Encode(strings.Repeat("a", 100))
	uassert.Equal(t, 4, Ratio(strings.Repeat("a", 100), enc2))
	uassert.Equal(t, 0, Ratio("", ""))
}
