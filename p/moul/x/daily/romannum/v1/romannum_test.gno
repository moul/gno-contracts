package romannum

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestToRoman(t *testing.T) {
	cases := []struct {
		in   int
		want string
	}{
		{1, "I"},
		{4, "IV"},
		{9, "IX"},
		{40, "XL"},
		{90, "XC"},
		{400, "CD"},
		{900, "CM"},
		{1994, "MCMXCIV"},
		{2024, "MMXXIV"},
		{3999, "MMMCMXCIX"},
	}
	for _, c := range cases {
		uassert.Equal(t, c.want, ToRoman(c.in))
	}
}

func TestParseRoman(t *testing.T) {
	// canonical numerals round-trip back to their value
	good := []struct {
		in   string
		want int
	}{
		{"I", 1},
		{"IV", 4},
		{"mmxxiv", 2024}, // case-insensitive
		{" XLII ", 42},   // trimmed
		{"MMMCMXCIX", 3999},
	}
	for _, c := range good {
		got, ok := parseRoman(c.in)
		uassert.True(t, ok)
		uassert.Equal(t, c.want, got)
	}

	// malformed / non-canonical forms are rejected
	bad := []string{"", "IIII", "VV", "IC", "MMMM", "XIↃ", "ABC"}
	for _, s := range bad {
		_, ok := parseRoman(s)
		uassert.False(t, ok)
	}
}

func TestRoundTrip(t *testing.T) {
	for n := 1; n <= 3999; n++ {
		got, ok := parseRoman(ToRoman(n))
		uassert.True(t, ok)
		uassert.Equal(t, n, got)
	}
}
