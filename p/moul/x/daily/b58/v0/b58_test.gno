package b58

import (
	"encoding/hex"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// Known Bitcoin Base58 test vectors (hex input → Base58 string).
var vectors = []struct {
	hexIn string
	b58   string
}{
	{"", ""},
	{"61", "2g"},
	{"626262", "a3gV"},
	{"636363", "aPEr"},
	{"73696d706c792061206c6f6e6720737472696e67", "2cFupjhnEsSn59qHXstmK2ffpLv2"},
	{"516b6fcd0f", "ABnLTmg"},
	{"bf4f89001e670274dd", "3SEo3LWLoPntC"},
	{"572e4794", "3EFU7m"},
	{"ecac89cad93923c02321", "EJDM8drfXA6uyA"},
	{"10c8511e", "Rt5zm"},
	{"00000000000000000000", "1111111111"},
	{"00eb15231dfceb60925886b67d065299925915aeb172c06647", "1NS17iag9jJgTHD1VXjvLCEnZuQ3rJDE9L"},
}

func TestEncodeVectors(t *testing.T) {
	for _, v := range vectors {
		in, err := hex.DecodeString(v.hexIn)
		uassert.NoError(t, err)
		got := Encode(in)
		uassert.Equal(t, v.b58, got)
	}
}

func TestDecodeVectors(t *testing.T) {
	for _, v := range vectors {
		want, err := hex.DecodeString(v.hexIn)
		uassert.NoError(t, err)
		got := Decode(v.b58)
		uassert.Equal(t, hex.EncodeToString(want), hex.EncodeToString(got))
	}
}

func TestRoundTrip(t *testing.T) {
	inputs := []string{
		"",
		"00",
		"0000ff",
		"deadbeef",
		"68656c6c6f20776f726c64", // "hello world"
		"ffffffffffffffff",
	}
	for _, hx := range inputs {
		raw, err := hex.DecodeString(hx)
		uassert.NoError(t, err)
		back := Decode(Encode(raw))
		uassert.Equal(t, hex.EncodeToString(raw), hex.EncodeToString(back))
	}
}

func TestLeadingZeros(t *testing.T) {
	uassert.Equal(t, "1", Encode([]byte{0}))
	uassert.Equal(t, "11", Encode([]byte{0, 0}))
	// One leading zero byte + a nonzero byte.
	got := Decode("1" + Encode([]byte{0x2a}))
	uassert.Equal(t, "002a", hex.EncodeToString(got))
}

func TestIsValid(t *testing.T) {
	uassert.True(t, IsValid("2cFupjhnEsSn59qHXstmK2ffpLv2"))
	uassert.True(t, IsValid("")) // empty is trivially valid
	uassert.False(t, IsValid("0OIl"))  // all four excluded characters
	uassert.False(t, IsValid("abc?"))  // punctuation not in alphabet
}

func TestDecodeInvalid(t *testing.T) {
	// A '0' is not part of the Base58 alphabet → nil.
	uassert.Equal(t, true, Decode("invalid0char") == nil)
}
