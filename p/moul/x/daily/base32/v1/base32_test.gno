package base32

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// The RFC 4648 §10 test vectors — every partial-group length.
func TestRFC4648Vectors(t *testing.T) {
	cases := []struct{ in, want string }{
		{"", ""},
		{"f", "MY======"},
		{"fo", "MZXQ===="},
		{"foo", "MZXW6==="},
		{"foob", "MZXW6YQ="},
		{"fooba", "MZXW6YTB"},
		{"foobar", "MZXW6YTBOI======"},
	}
	for _, c := range cases {
		got, err := Encode(c.in)
		uassert.NoError(t, err)
		uassert.Equal(t, c.want, got)
	}
}

func TestRFC4648RoundTrip(t *testing.T) {
	for _, s := range []string{"", "f", "fo", "foo", "foob", "fooba", "foobar", "hello world"} {
		enc, err := Encode(s)
		uassert.NoError(t, err)
		dec, err2 := Decode(enc)
		uassert.NoError(t, err2)
		uassert.Equal(t, s, dec)
	}
}

func TestUnpadded(t *testing.T) {
	got, _ := EncodeUnpadded("foobar")
	uassert.Equal(t, "MZXW6YTBOI", got)
	dec, err := Decode(got) // decoding tolerates the missing padding
	uassert.NoError(t, err)
	uassert.Equal(t, "foobar", dec)
}

func TestDecodeToleratesLowercase(t *testing.T) {
	dec, err := Decode("mzxw6ytboi")
	uassert.NoError(t, err)
	uassert.Equal(t, "foobar", dec)
}

func TestCrockfordRoundTrip(t *testing.T) {
	for _, s := range []string{"", "f", "foo", "foobar", "hello"} {
		enc, err := EncodeCrockford(s)
		uassert.NoError(t, err)
		dec, err2 := DecodeCrockford(enc)
		uassert.NoError(t, err2)
		uassert.Equal(t, s, dec)
	}
}

// The point of Crockford: a mis-typed identifier still decodes.
func TestCrockfordIsForgiving(t *testing.T) {
	enc, _ := EncodeCrockford("hello")
	want, _ := DecodeCrockford(enc)

	// lowercase
	got, err := DecodeCrockford(strings.ToLower(enc))
	uassert.NoError(t, err)
	uassert.Equal(t, want, got)

	// hyphens are ignored, wherever they land
	got2, err2 := DecodeCrockford(enc[:2] + "-" + enc[2:])
	uassert.NoError(t, err2)
	uassert.Equal(t, want, got2)

	// O reads as 0, I and L read as 1
	a, _ := DecodeCrockford("0")
	b, _ := DecodeCrockford("O")
	uassert.Equal(t, a, b)
	c, _ := DecodeCrockford("1")
	d, _ := DecodeCrockford("I")
	e, _ := DecodeCrockford("L")
	uassert.Equal(t, c, d)
	uassert.Equal(t, c, e)
}

// U is excluded from the Crockford alphabet on purpose.
func TestCrockfordExcludesU(t *testing.T) {
	uassert.Equal(t, -1, strings.IndexByte(CrockfordAlphabet, 'U'))
	_, err := DecodeCrockford("U")
	uassert.ErrorIs(t, err, ErrCorrupt)
}

func TestDecodeRejectsGarbage(t *testing.T) {
	for _, s := range []string{"!!!", "MZXW6YTB@", "0189"} { // 0/1/8/9 are not RFC 4648
		_, err := Decode(s)
		uassert.Error(t, err)
	}
}

// Leftover bits must be zero padding, never smuggled data.
func TestDecodeRejectsNonZeroLeftoverBits(t *testing.T) {
	// "MB" would leave non-zero bits after emitting one byte
	_, err := Decode("MB")
	uassert.ErrorIs(t, err, ErrCorrupt)
}

func TestTooLong(t *testing.T) {
	_, err := Encode(strings.Repeat("a", MaxLen+1))
	uassert.ErrorIs(t, err, ErrTooLong)
}

// Padded output is always a multiple of 8 characters.
func TestPaddingLength(t *testing.T) {
	for _, s := range []string{"f", "fo", "foo", "foob", "fooba", "foobar"} {
		enc, _ := Encode(s)
		uassert.Equal(t, 0, len(enc)%8)
	}
}
