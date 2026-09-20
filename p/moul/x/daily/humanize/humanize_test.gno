package humanize

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestBytes(t *testing.T) {
	cases := []struct {
		in   int64
		want string
	}{
		{0, "0 B"},
		{999, "999 B"},
		{1023, "1023 B"},
		{1024, "1 KiB"},
		{1536, "1.5 KiB"},
		{1048576, "1 MiB"},
		{1572864, "1.5 MiB"},
		{1073741824, "1 GiB"},
		{-1536, "-1.5 KiB"},
		{-10, "-10 B"},
	}
	for _, c := range cases {
		uassert.Equal(t, c.want, Bytes(c.in))
	}
}

func TestComma(t *testing.T) {
	cases := []struct {
		in   int64
		want string
	}{
		{0, "0"}, {1, "1"}, {999, "999"}, {1000, "1,000"},
		{1234567, "1,234,567"}, {-1234567, "-1,234,567"},
	}
	for _, c := range cases {
		uassert.Equal(t, c.want, Comma(c.in))
	}
}

// The teens are the trap: 11/12/13 take "th" despite ending in 1/2/3.
func TestOrdinalTeens(t *testing.T) {
	cases := []struct {
		in   int64
		want string
	}{
		{1, "1st"}, {2, "2nd"}, {3, "3rd"}, {4, "4th"},
		{11, "11th"}, {12, "12th"}, {13, "13th"},
		{21, "21st"}, {22, "22nd"}, {23, "23rd"},
		{111, "111th"}, {112, "112th"}, {113, "113th"},
		{101, "101st"}, {0, "0th"},
	}
	for _, c := range cases {
		uassert.Equal(t, c.want, Ordinal(c.in))
	}
}

func TestPlural(t *testing.T) {
	uassert.Equal(t, "1 block", Plural(1, "block", ""))
	uassert.Equal(t, "2 blocks", Plural(2, "block", ""))
	uassert.Equal(t, "0 blocks", Plural(0, "block", ""))
	uassert.Equal(t, "2 mice", Plural(2, "mouse", "mice"))
	uassert.Equal(t, "-1 block", Plural(-1, "block", ""))
}

func TestBlocks(t *testing.T) {
	uassert.Equal(t, "now", Blocks(0))
	uassert.Equal(t, "1 block", Blocks(1))
	uassert.Equal(t, "9 blocks", Blocks(9))
	uassert.Equal(t, "~10 blocks", Blocks(15))
	uassert.Equal(t, "~1,200 blocks", Blocks(1234))
	uassert.Equal(t, "in the past", Blocks(-5))
}

// Truncate counts runes, so multi-byte text is never cut mid-character.
func TestTruncateCountsRunes(t *testing.T) {
	uassert.Equal(t, "hello", Truncate("hello", 10))
	uassert.Equal(t, "hell…", Truncate("hello!", 5))
	uassert.Equal(t, "…", Truncate("hello", 1))
	uassert.Equal(t, "", Truncate("hello", 0))
	uassert.Equal(t, "éé", Truncate("éé", 2))
	uassert.Equal(t, "é…", Truncate("ééé", 2)) // not sliced mid-rune
}
