package quotedprintable

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestEncode(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want string
	}{
		{"empty", "", ""},
		{"plain ascii", "hello", "hello"},
		{"equals is never literal", "a=b", "a=3Db"},
		{"interior space stays literal", "hello world", "hello world"},
		{"trailing space is encoded", "hello ", "hello=20"},
		{"trailing tab is encoded", "hi\t", "hi=09"},
		{"line feed is a byte like any other", "a\nb", "a=0Ab"},
		{"crlf is two bytes", "a\r\nb", "a=0D=0Ab"},
		{"latin1 high byte", "caf\xe9", "caf=E9"},
		{"utf8 is just bytes", "café", "caf=C3=A9"},
		{"tilde and bang are literal", "!~", "!~"},
		{"del is encoded", "\x7f", "=7F"},
		{"nul is encoded", "\x00", "=00"},
	}
	for _, tc := range cases {
		got, err := Encode(tc.in)
		uassert.NoError(t, err, tc.name)
		uassert.Equal(t, tc.want, got, tc.name)
	}
}

func TestEncodeWrapsAt76(t *testing.T) {
	// 200 literal characters: every output line must fit in 76 columns,
	// including the trailing soft-break '='.
	got, err := Encode(strings.Repeat("a", 200))
	uassert.NoError(t, err)
	lines := strings.Split(got, "\r\n")
	uassert.Equal(t, 3, len(lines), "200 'a' wrap into three lines")
	for _, l := range lines {
		uassert.True(t, len(l) <= 76, "line within 76 columns: "+l)
	}
	uassert.Equal(t, 76, len(lines[0]), "first line is 75 characters plus the soft-break =")
	uassert.True(t, strings.HasSuffix(lines[0], "="), "soft break ends the line")
	uassert.Equal(t, strings.Repeat("a", 200), mustDecode(t, got), "wrapping round-trips")
}

func TestEncodeNeverEndsALineWithWhitespace(t *testing.T) {
	// A space landing near the wrap column must be encoded, because every
	// decoder and every transport strips whitespace at end of line.
	for n := 60; n < 90; n++ {
		in := strings.Repeat("a", n) + " " + strings.Repeat("b", 20)
		got, err := Encode(in)
		uassert.NoError(t, err)
		for _, l := range strings.Split(got, "\r\n") {
			content := strings.TrimSuffix(l, "=")
			uassert.False(t, strings.HasSuffix(content, " "),
				"line ends with a literal space: "+l)
			uassert.False(t, strings.HasSuffix(content, "\t"),
				"line ends with a literal tab: "+l)
			uassert.True(t, len(l) <= 76, "line within 76 columns: "+l)
		}
		uassert.Equal(t, in, mustDecode(t, got), "round-trip at n")
	}
}

func TestDecode(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want string
	}{
		{"empty", "", ""},
		{"plain", "hello", "hello"},
		{"hex pair", "a=3Db", "a=b"},
		{"lowercase hex is accepted", "caf=e9", "caf\xe9"},
		{"soft break disappears", "he=\r\nllo", "hello"},
		{"bare lf soft break", "he=\nllo", "hello"},
		{"hard break is data", "a\r\nb", "a\r\nb"},
		{"trailing whitespace before a hard break is dropped", "a  \r\nb", "a\r\nb"},
		{"trailing whitespace at the very end is dropped", "a  ", "a"},
	}
	for _, tc := range cases {
		got, err := Decode(tc.in)
		uassert.NoError(t, err, tc.name)
		uassert.Equal(t, tc.want, got, tc.name)
	}
}

func TestDecodeRejectsCorrupt(t *testing.T) {
	for _, in := range []string{"=", "=4", "=zz", "a=4z", "=G0", "a=="} {
		_, err := Decode(in)
		uassert.ErrorIs(t, err, ErrCorrupt, "corrupt input accepted: "+in)
	}
}

func TestRoundTrip(t *testing.T) {
	inputs := []string{
		"",
		"hello world",
		"café ☕",
		"a\r\nb\r\nc",
		"   leading and trailing   ",
		"=?utf-8?q?already encoded??=",
		strings.Repeat("x y ", 100),
		"\x00\x01\x02\xfd\xfe\xff",
	}
	for _, in := range inputs {
		enc, err := Encode(in)
		uassert.NoError(t, err)
		uassert.Equal(t, in, mustDecode(t, enc), "round-trip")
	}
}

func TestLimit(t *testing.T) {
	_, err := Encode(strings.Repeat("a", MaxLen+1))
	uassert.ErrorIs(t, err, ErrTooLong)
	_, err = Decode(strings.Repeat("a", MaxLen*4+1))
	uassert.ErrorIs(t, err, ErrTooLong)
}

func TestEncodeWord(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want string
	}{
		{"plain", "hello", "=?UTF-8?Q?hello?="},
		{"space becomes underscore", "hello world", "=?UTF-8?Q?hello_world?="},
		{"underscore must be escaped", "a_b", "=?UTF-8?Q?a=5Fb?="},
		{"question mark must be escaped", "why?", "=?UTF-8?Q?why=3F?="},
		{"equals must be escaped", "a=b", "=?UTF-8?Q?a=3Db?="},
		{"utf8", "café", "=?UTF-8?Q?caf=C3=A9?="},
		{"tab is encoded", "a\tb", "=?UTF-8?Q?a=09b?="},
	}
	for _, tc := range cases {
		got, err := EncodeWord(tc.in)
		uassert.NoError(t, err, tc.name)
		uassert.Equal(t, tc.want, got, tc.name)
	}
}

func TestEncodeWordRefusesToExceed75(t *testing.T) {
	_, err := EncodeWord(strings.Repeat("a", 100))
	uassert.ErrorIs(t, err, ErrWordTooLong)
	// 63 literals plus the 12-character wrapper is exactly 75: the limit.
	got, err := EncodeWord(strings.Repeat("a", 63))
	uassert.NoError(t, err)
	uassert.Equal(t, 75, len(got))
}

func TestDecodeWord(t *testing.T) {
	cases := []struct {
		name string
		in   string
		want string
	}{
		{"plain", "=?UTF-8?Q?hello?=", "hello"},
		{"underscore is a space", "=?UTF-8?Q?hello_world?=", "hello world"},
		{"lowercase q", "=?utf-8?q?caf=c3=a9?=", "café"},
		{"any charset label passes through", "=?iso-8859-1?Q?caf=E9?=", "caf\xe9"},
		{"not a word at all", "hello", "hello"},
	}
	for _, tc := range cases {
		got, err := DecodeWord(tc.in)
		uassert.NoError(t, err, tc.name)
		uassert.Equal(t, tc.want, got, tc.name)
	}
}

func TestDecodeWordRejectsBase64(t *testing.T) {
	_, err := DecodeWord("=?UTF-8?B?aGVsbG8=?=")
	uassert.ErrorIs(t, err, ErrUnsupportedEncoding)
}

func TestWordRoundTrip(t *testing.T) {
	for _, in := range []string{"hello world", "café", "a_b=c?d", "   "} {
		enc, err := EncodeWord(in)
		uassert.NoError(t, err)
		got, err := DecodeWord(enc)
		uassert.NoError(t, err)
		uassert.Equal(t, in, got, "word round-trip")
	}
}

// TestBodyAndHeaderDisagree pins the one fact the demo exists to show: the two
// rulesets encode the same bytes differently, so a body codec cannot be reused
// for a header.
func TestBodyAndHeaderDisagree(t *testing.T) {
	body, err := Encode("why not?")
	uassert.NoError(t, err)
	word, err := EncodeWord("why not?")
	uassert.NoError(t, err)
	uassert.Equal(t, "why not?", body, "a body leaves space and '?' alone")
	uassert.Equal(t, "=?UTF-8?Q?why_not=3F?=", word, "a header encodes both")
}

func mustDecode(t *testing.T, s string) string {
	t.Helper()
	got, err := Decode(s)
	uassert.NoError(t, err, "decode")
	return got
}
