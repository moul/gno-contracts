package ascii85

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// The encode vectors are the classic btoa set plus the partial-group lengths
// and the zero shortcut. Every expectation was produced by Go's
// encoding/ascii85 on 2026-11-05 and copied, not computed by hand.
func TestEncode(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want string
	}{
		{"empty", "", ""},
		{"one byte", "s", "Er"},
		{"two bytes", "su", "F*."},
		{"three bytes", "sur", "F*2L"},
		{"four bytes", "sure", "F*2M7"},
		{"five bytes", "sure.", "F*2M7/c"},
		{"six bytes", "sure.!", "F*2M7/g1"},
		{"one full group", "Man ", "9jqo^"},
		{"the btoa sentence", "Man is distinguished", "9jqo^BlbD-BleB1DJ+*+F(f,q"},
		{"zero group is z", "\x00\x00\x00\x00", "z"},
		{"z then a partial group", "\x00\x00\x00\x00\x00", "z!!"},
		{"two zero groups", "\x00\x00\x00\x00\x00\x00\x00\x00", "zz"},
		{"z only when the group is full", "\x00\x00\x00", "!!!!"},
		{"a single zero byte", "\x00", "!!"},
		{"four zeros on a group boundary", "abcd\x00\x00\x00\x00efgh", "@:E_WzAS,Rg"},
		{"four zeros straddling two groups", "abc\x00\x00\x00\x00def", "@:E^H!!!\"0AS("},
		{"the largest group", "\xff\xff\xff\xff", "s8W-!"},
		{"the largest partial group", "\xff\xff\xff", "s8W*"},
		{"hello world", "Hello World!", "87cURD]i,\"Ebo80"},
		{"gno.land", "gno.land", "B5VW?Cgh3l"},
		{"the package name", "ascii85", "@<5pmBfIs"},
	}
	for _, tc := range cases {
		got, err := Encode(tc.in)
		uassert.NoError(t, err, tc.name)
		uassert.Equal(t, tc.want, got, tc.name)
	}
}

func TestEncodeFramed(t *testing.T) {
	got, err := EncodeFramed("Hello World!")
	uassert.NoError(t, err)
	uassert.Equal(t, "<~87cURD]i,\"Ebo80~>", got)

	// Empty input still produces the delimiters, so a reader can tell an
	// empty stream from a missing one.
	got, err = EncodeFramed("")
	uassert.NoError(t, err)
	uassert.Equal(t, "<~~>", got)
}

func TestDecode(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want string
	}{
		{"empty", "", ""},
		{"bare", "87cURD]i,\"Ebo80", "Hello World!"},
		{"framed", "<~87cURD]i,\"Ebo80~>", "Hello World!"},
		{"empty frame", "<~~>", ""},
		{"a line break inside a group", "87cUR\nD]i,\"Ebo80", "Hello World!"},
		{"spaces and tabs everywhere", " 87 cUR\tD]i,\"Ebo80 ", "Hello World!"},
		{"the z shortcut", "z", "\x00\x00\x00\x00"},
		{"two shortcuts", "zz", "\x00\x00\x00\x00\x00\x00\x00\x00"},
		{"a shortcut beside data", "@:E_WzAS,Rg", "abcd\x00\x00\x00\x00efgh"},
		{"the largest group", "s8W-!", "\xff\xff\xff\xff"},
		{"a two-character group", "!!", "\x00"},
	}
	for _, tc := range cases {
		got, err := Decode(tc.in)
		uassert.NoError(t, err, tc.name)
		uassert.Equal(t, tc.want, got, tc.name)
	}
}

// TestDecodeRefusesOverflow is the reason this package is not a port of the
// standard library's. Both inputs below are accepted by Go's
// encoding/ascii85, which holds the group in a uint32: "s8W-\"" is 2^32 and
// wraps to the same four zero bytes as "z", and "uuuuu" wraps to four bytes
// that are nowhere in the text. Measured 2026-11-05.
func TestDecodeRefusesOverflow(t *testing.T) {
	cases := []struct {
		name string
		in   string
	}{
		{"exactly 2^32", "s8W-\""},
		{"every digit at its maximum", "uuuuu"},
		{"one past the largest group", "s8W-#"},
		{"overflow inside a longer stream", "87cURuuuuu"},
		{"overflow in a framed stream", "<~uuuuu~>"},
	}
	for _, tc := range cases {
		got, err := Decode(tc.in)
		uassert.ErrorIs(t, err, ErrOverflow, tc.name)
		uassert.Equal(t, "", got, tc.name)
	}

	// The group one below the limit is still fine, so the check is a
	// boundary and not a blanket refusal of large groups.
	got, err := Decode("s8W-!")
	uassert.NoError(t, err)
	uassert.Equal(t, "\xff\xff\xff\xff", got)
}

func TestDecodeRejects(t *testing.T) {
	cases := []struct {
		name string
		in   string
	}{
		{"a lone character", "!"},
		{"a lone character after a full group", "87cUR!"},
		{"a character below the alphabet", "87cUR\x01"},
		{"a character above the alphabet", "87cURv"},
		{"the shortcut inside a group", "87cURD]i,\"Ebo8z0"},
		{"a closing delimiter with no opening one", "87cURD]i,\"Ebo80~>"},
		{"an opening delimiter with no closing one", "<~87cURD]i,\"Ebo80"},
		{"delimiters in the middle", "87cUR<~D]i,\"Ebo80~>"},
		{"nothing but a closing delimiter", "~>"},
	}
	for _, tc := range cases {
		got, err := Decode(tc.in)
		uassert.ErrorIs(t, err, ErrCorrupt, tc.name)
		uassert.Equal(t, "", got, tc.name)
	}
}

func TestRoundTrip(t *testing.T) {
	// Every byte value, which exercises the whole alphabet and lands the
	// final group on a four-byte boundary.
	var all strings.Builder
	for i := 0; i < 256; i++ {
		all.WriteByte(byte(i))
	}
	enc, err := Encode(all.String())
	uassert.NoError(t, err)
	// 256 bytes is 64 groups, one of which is the zero group written as z.
	uassert.Equal(t, 320, len(enc))

	dec, err := Decode(enc)
	uassert.NoError(t, err)
	uassert.Equal(t, all.String(), dec)

	// Every remainder, so the padding rule is covered at each length.
	for n := 0; n < 9; n++ {
		src := all.String()[:n]
		enc, err := Encode(src)
		uassert.NoError(t, err)
		dec, err := Decode(enc)
		uassert.NoError(t, err)
		uassert.Equal(t, src, dec)

		framed, err := EncodeFramed(src)
		uassert.NoError(t, err)
		dec, err = Decode(framed)
		uassert.NoError(t, err)
		uassert.Equal(t, src, dec)
	}
}

// TestOverhead pins the claim the package doc makes: five characters per four
// bytes, against base64's four per three.
func TestOverhead(t *testing.T) {
	src := strings.Repeat("x", 400)
	enc, err := Encode(src)
	uassert.NoError(t, err)
	uassert.Equal(t, 500, len(enc))
}

func TestLimits(t *testing.T) {
	_, err := Encode(strings.Repeat("x", MaxLen))
	uassert.NoError(t, err)

	_, err = Encode(strings.Repeat("x", MaxLen+1))
	uassert.ErrorIs(t, err, ErrTooLong)

	_, err = EncodeFramed(strings.Repeat("x", MaxLen+1))
	uassert.ErrorIs(t, err, ErrTooLong)

	_, err = Decode(strings.Repeat("!", MaxTextLen+1))
	uassert.ErrorIs(t, err, ErrTooLong)

	// MaxTextLen leaves room for the longest stream Encode can produce,
	// framed and line-broken, which is the only reason the two differ.
	enc, err := EncodeFramed(strings.Repeat("x", MaxLen))
	uassert.NoError(t, err)
	uassert.True(t, len(enc) <= MaxTextLen, "framed maximum fits MaxTextLen")
}
