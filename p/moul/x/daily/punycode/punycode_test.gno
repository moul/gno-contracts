package punycode

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// The RFC 3492 section 7.1 vectors that can be written as literals here, plus
// the ones every IDN tutorial uses. Each pair was checked against an
// independent implementation before being pinned.
var vectors = []struct{ in, want string }{
	{"", ""},
	{"abc", "abc-"},
	{"bücher", "bcher-kva"},
	{"münchen", "mnchen-3ya"},
	{"ñ", "ida"},
	{"€", "lzg"},
	{"αβγ", "mxacd"},
	{"Ελληνικά", "twa0c6aifdar"},
	{"ру", "p1ag"},
	{"мир", "h1ahn"},
	{"日本語", "wgv71a119e"},
	{"例え", "r8jz45g"},
	{"3年B組金八先生", "3B-ww4c5e180e575a65lsy2b"},   // RFC 3492 (L)
	{"ひとつ屋根の下2", "2-u9tlzr9756bt3uc0v"},        // RFC 3492 (O)
	{"そのスピードで", "d9juau41awczczp"},             // RFC 3492 (R)
	{"-> $1.00 <-", "-> $1.00 <--"},            // RFC 3492 (S)
}

func TestEncodeVectors(t *testing.T) {
	for _, c := range vectors {
		got, err := Encode(c.in)
		uassert.NoError(t, err)
		uassert.Equal(t, c.want, got)
	}
}

func TestDecodeVectors(t *testing.T) {
	for _, c := range vectors {
		got, err := Decode(c.want)
		uassert.NoError(t, err)
		uassert.Equal(t, c.in, got)
	}
}

func TestRoundTrip(t *testing.T) {
	for _, s := range []string{"", "a", "héllo wörld", "日本語テスト", "ascii-only", "ü", "aüa"} {
		enc, err := Encode(s)
		uassert.NoError(t, err)
		dec, err2 := Decode(enc)
		uassert.NoError(t, err2)
		uassert.Equal(t, s, dec)
	}
}

// An all-basic string still gets the delimiter, or the decoder would read the
// whole thing as deltas.
func TestBasicOnlyKeepsDelimiter(t *testing.T) {
	got, err := Encode("hello")
	uassert.NoError(t, err)
	uassert.Equal(t, "hello-", got)

	// without it, "hello" is not a valid encoding of "hello"
	dec, err2 := Decode("hello")
	if err2 == nil {
		uassert.NotEqual(t, "hello", dec)
	}
}

func TestDomain(t *testing.T) {
	cases := []struct{ in, want string }{
		{"example.com", "example.com"},
		{"bücher.example", "xn--bcher-kva.example"},
		{"münchen.de", "xn--mnchen-3ya.de"},
		{"日本語.jp", "xn--wgv71a119e.jp"},
		{"a.bücher.日本語", "a.xn--bcher-kva.xn--wgv71a119e"},
		{"", ""},
	}
	for _, c := range cases {
		got, err := EncodeDomain(c.in)
		uassert.NoError(t, err)
		uassert.Equal(t, c.want, got)

		back, err2 := DecodeDomain(c.want)
		uassert.NoError(t, err2)
		uassert.Equal(t, c.in, back)
	}
}

// A label already in ACE form is left alone rather than double-encoded.
func TestEncodeDomainIsIdempotentOnASCII(t *testing.T) {
	once, err := EncodeDomain("bücher.example")
	uassert.NoError(t, err)
	twice, err2 := EncodeDomain(once)
	uassert.NoError(t, err2)
	uassert.Equal(t, once, twice)
}

func TestDecodeRejectsNonASCII(t *testing.T) {
	_, err := Decode("bücher")
	uassert.ErrorIs(t, err, ErrInvalid)
}

func TestDecodeRejectsBadDigit(t *testing.T) {
	for _, s := range []string{"a-!", "a-A", "a-_", "-abc"} {
		_, err := Decode(s)
		uassert.Error(t, err)
	}
}

// A truncated extended part must fail, not silently stop mid-number.
func TestDecodeRejectsTruncated(t *testing.T) {
	_, err := Decode("bcher-kv")
	uassert.Error(t, err)
}

// The property that matters on chain: a crafted input cannot make the decoder
// walk past the valid code point range. It returns an error instead.
func TestDecodeRejectsOverflow(t *testing.T) {
	_, err := Decode("a-" + strings.Repeat("9", 40))
	uassert.Error(t, err)
}

func TestTooLong(t *testing.T) {
	_, err := Encode(strings.Repeat("a", MaxLen+1))
	uassert.ErrorIs(t, err, ErrTooLong)

	_, err2 := Decode(strings.Repeat("a", MaxLen+1))
	uassert.ErrorIs(t, err2, ErrTooLong)
}

// Decoding is total over every ASCII input: it returns, with a value or an
// error, and never panics. A realm rendering a user-supplied label depends on
// this.
func TestDecodeIsTotal(t *testing.T) {
	for _, s := range []string{"", "-", "--", "---", "a", "-a", "a-", "xn--", "zzzzzzzzzz", "0", "a-0", "a-" + strings.Repeat("z", 60)} {
		_, _ = Decode(s)
	}
}
