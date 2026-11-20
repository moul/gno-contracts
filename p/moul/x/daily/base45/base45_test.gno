package base45

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// The RFC 9285 §4.4 test vectors. "AB" and "ietf!" are the two that pin the
// byte order: base45 emits each group least-significant character first, so a
// decoder written the obvious way round produces "8BB" here and passes every
// round-trip test it will ever be given.
func TestRFC9285Vectors(t *testing.T) {
	cases := []struct{ in, want string }{
		{"", ""},
		{"AB", "BB8"},
		{"Hello!!", "%69 VD92EX0"},
		{"base-45", "UJCLQE7W581"},
		{"ietf!", "QED8WEX0"},
	}
	for _, c := range cases {
		got, err := Encode(c.in)
		uassert.NoError(t, err)
		uassert.Equal(t, c.want, got)

		back, err2 := Decode(c.want)
		uassert.NoError(t, err2)
		uassert.Equal(t, c.in, back)
	}
}

func TestRoundTrip(t *testing.T) {
	for _, s := range []string{
		"", "a", "ab", "abc", "abcd", "hello world",
		"\x00", "\x00\x00", "\xff\xff", "\x00\xff\x00\xff\x00",
	} {
		enc, err := Encode(s)
		uassert.NoError(t, err)
		dec, err2 := Decode(enc)
		uassert.NoError(t, err2)
		uassert.Equal(t, s, dec)
	}
}

// Every byte value survives a round trip, including the ones that are not
// valid UTF-8 on their own.
func TestEveryByte(t *testing.T) {
	src := make([]byte, 256)
	for i := 0; i < 256; i++ {
		src[i] = byte(i)
	}
	enc, err := EncodeBytes(src)
	uassert.NoError(t, err)
	uassert.Equal(t, 384, len(enc)) // 128 pairs, 3 characters each
	dec, err2 := DecodeBytes(enc)
	uassert.NoError(t, err2)
	uassert.Equal(t, 256, len(dec))
	for i := 0; i < 256; i++ {
		uassert.Equal(t, i, int(dec[i]))
	}
}

func TestEncodedLen(t *testing.T) {
	cases := []struct{ in, want int }{{0, 0}, {1, 2}, {2, 3}, {3, 5}, {4, 6}, {7, 11}}
	for _, c := range cases {
		uassert.Equal(t, c.want, EncodedLen(c.in))
	}
}

// A length of 3n+1 can never be produced by the encoder: groups are three
// characters and the odd trailing byte is two.
func TestDecodeRejectsStrayCharacter(t *testing.T) {
	for _, s := range []string{"B", "BB8B", "BB8BB8B"} {
		_, err := Decode(s)
		uassert.ErrorIs(t, err, ErrCorrupt)
	}
}

func TestDecodeRejectsCharacterOutsideAlphabet(t *testing.T) {
	for _, s := range []string{"bb8", "BB8;", "B#8", "BB\n"} {
		_, err := Decode(s)
		uassert.ErrorIs(t, err, ErrCorrupt)
	}
}

// A three-character group decodes to one 16-bit value, so a group above
// 0xFFFF is a string no encoder emitted. "FGW" is exactly 0xFFFF and "GGW" is
// 0x10000: one character apart, and the second must be refused rather than
// truncated.
func TestDecodeRejectsOverflowingTriple(t *testing.T) {
	ok, err := DecodeBytes("FGW")
	uassert.NoError(t, err)
	uassert.Equal(t, 2, len(ok))
	uassert.Equal(t, 0xFF, int(ok[0]))
	uassert.Equal(t, 0xFF, int(ok[1]))

	_, err2 := DecodeBytes("GGW")
	uassert.ErrorIs(t, err2, ErrOverflow)
}

// Same boundary on the trailing pair, which decodes to one byte: "U5" is 255
// and "V5" is 256.
func TestDecodeRejectsOverflowingPair(t *testing.T) {
	ok, err := DecodeBytes("U5")
	uassert.NoError(t, err)
	uassert.Equal(t, 1, len(ok))
	uassert.Equal(t, 0xFF, int(ok[0]))

	_, err2 := DecodeBytes("V5")
	uassert.ErrorIs(t, err2, ErrOverflow)
}

func TestTooLong(t *testing.T) {
	src := make([]byte, MaxLen+1)
	_, err := EncodeBytes(src)
	uassert.ErrorIs(t, err, ErrTooLong)

	long := ""
	for len(long) <= MaxLen {
		long += "BB8"
	}
	_, err2 := Decode(long)
	uassert.ErrorIs(t, err2, ErrTooLong)
}

func TestAlphabetIsFortyFiveDistinctCharacters(t *testing.T) {
	uassert.Equal(t, 45, len(Alphabet))
	seen := map[byte]bool{}
	for i := 0; i < len(Alphabet); i++ {
		uassert.False(t, seen[Alphabet[i]])
		seen[Alphabet[i]] = true
	}
}
