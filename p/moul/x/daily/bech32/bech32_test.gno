package bech32

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// BIP-173 §Test vectors: strings that must decode with the Bech32 constant.
func TestValidBech32(t *testing.T) {
	cases := []struct{ s, hrp string }{
		{"A12UEL5L", "a"},
		{"a12uel5l", "a"},
		{"?1ezyfcl", "?"},
		{"abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw", "abcdef"},
		{"split1checkupstagehandshakeupstreamerranterredcaperred2y9e3w", "split"},
	}
	for _, c := range cases {
		hrp, data, v, err := Decode(c.s)
		uassert.NoError(t, err, c.s)
		uassert.Equal(t, c.hrp, hrp)
		uassert.Equal(t, "bech32", v.String())
		// Re-encoding the decoded parts must reproduce the lowercase input.
		back, err2 := Encode(hrp, data)
		uassert.NoError(t, err2)
		uassert.Equal(t, lower(c.s), back)
	}
}

// BIP-350 §Test vectors: the same shapes under the Bech32m constant.
func TestValidBech32m(t *testing.T) {
	for _, c := range []struct{ s, hrp string }{
		{"A1LQFN3A", "a"},
		{"a1lqfn3a", "a"},
		{"?1v759aa", "?"},
		{"split1checkupstagehandshakeupstreamerranterredcaperredlc445v", "split"},
	} {
		hrp, data, v, err := Decode(c.s)
		uassert.NoError(t, err, c.s)
		uassert.Equal(t, c.hrp, hrp)
		uassert.Equal(t, "bech32m", v.String())
		back, err2 := EncodeVariant(hrp, data, Bech32m)
		uassert.NoError(t, err2)
		uassert.Equal(t, lower(c.s), back)
	}
}

// A gno.land address is a Bech32 string with hrp "g" over a 20-byte payload,
// which is the externally-anchored check that the checksum maths is right.
func TestGnoAddress(t *testing.T) {
	const addr = "g1manfred47kzduec920z88wfr64ylksmdcedlf5"
	hrp, payload, v, err := DecodeBytes(addr)
	uassert.NoError(t, err)
	uassert.Equal(t, "g", hrp)
	uassert.Equal(t, 20, len(payload))
	uassert.Equal(t, "bech32", v.String())

	back, err2 := EncodeBytes(hrp, payload)
	uassert.NoError(t, err2)
	uassert.Equal(t, addr, back)
}

// One flipped data character invalidates the checksum.
func TestBadChecksum(t *testing.T) {
	const addr = "g1manfred47kzduec920z88wfr64ylksmdcedlf5"
	broken := addr[:len(addr)-1] + "4"
	_, _, _, err := Decode(broken)
	uassert.ErrorIs(t, err, ErrChecksum)
}

func TestDecodeRejects(t *testing.T) {
	cases := []struct {
		s    string
		want error
	}{
		{"A12UEL5l", ErrMixedCase},
		{"abcdef", ErrNoSeparator},
		{"1qzzfhee", ErrInvalidHRP},  // empty human-readable part
		{"a1qqqqq", ErrTooShort},     // data part shorter than the 6-char checksum
		{"a1bqqqqqq", ErrInvalidChar}, // 'b' is not in the charset
	}
	for _, c := range cases {
		_, _, _, err := Decode(c.s)
		uassert.ErrorIs(t, err, c.want, c.s)
	}
}

func TestTooLong(t *testing.T) {
	long := "a1"
	for i := 0; i < MaxLen; i++ {
		long += "q"
	}
	_, _, _, err := Decode(long)
	uassert.ErrorIs(t, err, ErrTooLong)

	payload := make([]byte, 80)
	_, err2 := EncodeBytes("hrp", payload)
	uassert.ErrorIs(t, err2, ErrTooLong)
}

func TestConvertBits(t *testing.T) {
	// 8 -> 5 with padding, then back, is the identity.
	for _, in := range [][]byte{{}, {0x00}, {0xff}, {0xde, 0xad, 0xbe, 0xef}, {1, 2, 3, 4, 5, 6, 7}} {
		five, err := ConvertBits(in, 8, 5, true)
		uassert.NoError(t, err)
		eight, err2 := ConvertBits(five, 5, 8, false)
		uassert.NoError(t, err2)
		uassert.Equal(t, len(in), len(eight))
		for i := range in {
			uassert.Equal(t, int(in[i]), int(eight[i]))
		}
	}
	// Every produced group fits in 5 bits.
	five, _ := ConvertBits([]byte{0xff, 0xff}, 8, 5, true)
	for _, g := range five {
		uassert.True(t, g < 32)
	}
	// A 5-bit input holding a 6-bit value is refused.
	_, err := ConvertBits([]byte{32}, 5, 8, true)
	uassert.ErrorIs(t, err, ErrInvalidData)
	// An unsupported width is refused.
	_, err2 := ConvertBits([]byte{1}, 0, 5, true)
	uassert.ErrorIs(t, err2, ErrInvalidBits)
}

func TestEncodeRejects(t *testing.T) {
	_, err := Encode("", []byte{0})
	uassert.ErrorIs(t, err, ErrInvalidHRP)
	// A human-readable part must stay in the printable US-ASCII range.
	_, err2 := Encode("a\x7f", []byte{0})
	uassert.ErrorIs(t, err2, ErrInvalidHRP)
	// A data group wider than 5 bits is not representable.
	_, err3 := Encode("a", []byte{32})
	uassert.ErrorIs(t, err3, ErrInvalidData)
}

func TestVariantString(t *testing.T) {
	uassert.Equal(t, "bech32", Bech32.String())
	uassert.Equal(t, "bech32m", Bech32m.String())
}

func lower(s string) string {
	out := []byte(s)
	for i, c := range out {
		if c >= 'A' && c <= 'Z' {
			out[i] = c + 32
		}
	}
	return string(out)
}

// Why Bech32m exists. A Bech32 string whose final character is 'p' keeps a valid
// checksum when 'q' characters are inserted in front of that 'p', so a reader
// accepts a string it was never handed. Both of these verify under the Bech32
// constant, and they decode to different data parts.
func TestLengthExtensionWeakness(t *testing.T) {
	const base = "a1q3g6mnsp"
	const extended = "a1q3g6mnsqp"

	_, d1, v1, err := Decode(base)
	uassert.NoError(t, err)
	uassert.Equal(t, "bech32", v1.String())

	_, d2, v2, err2 := Decode(extended)
	uassert.NoError(t, err2, "the inserted 'q' does not break the Bech32 checksum")
	uassert.Equal(t, "bech32", v2.String())
	uassert.Equal(t, len(d1)+1, len(d2))

	// Bech32m's constant closes it: the same insertion on a Bech32m string of the
	// same shape is refused.
	_, _, _, err3 := Decode("a1q6dp699qp")
	uassert.ErrorIs(t, err3, ErrChecksum)
	_, _, vm, err4 := Decode("a1q6dp699p")
	uassert.NoError(t, err4)
	uassert.Equal(t, "bech32m", vm.String())
}

// Variant is an exported int, so a caller can hand over a value that is neither
// constant. Encoding one as Bech32 anyway would answer a question nobody asked.
func TestUnknownVariant(t *testing.T) {
	_, err := EncodeVariant("a", nil, Variant(2))
	uassert.ErrorIs(t, err, ErrInvalidVariant)
	_, err2 := EncodeVariant("a", nil, Variant(-1))
	uassert.ErrorIs(t, err2, ErrInvalidVariant)
	uassert.Equal(t, "invalid", Variant(2).String())
}

// ConvertBits promises ErrInvalidPadding, and a round trip never reaches it:
// the padded direction always lands on a group boundary.
func TestConvertBitsPadding(t *testing.T) {
	// Five bits in, eight out, unpadded: one group is not a whole byte.
	_, err := ConvertBits([]byte{1}, 5, 8, false)
	uassert.ErrorIs(t, err, ErrInvalidPadding)
	// Ten bits in, eight out: the two leftover bits are not zero, so they are
	// data the caller would lose rather than padding the encoder added.
	_, err2 := ConvertBits([]byte{0, 1}, 5, 8, false)
	uassert.ErrorIs(t, err2, ErrInvalidPadding)
	// The same ten bits with zero leftovers convert cleanly.
	out, err3 := ConvertBits([]byte{0, 4}, 5, 8, false)
	uassert.NoError(t, err3)
	uassert.Equal(t, 1, len(out))
}

// An oversized payload is refused before it is regrouped, so the work stays
// bounded by the 90-character format rather than by what the caller sent.
func TestEncodeBytesBoundsBeforeWork(t *testing.T) {
	// "g" plus the separator plus six checksum characters leaves 82 groups,
	// which is 51 whole bytes.
	uassert.Equal(t, 51, MaxPayloadLen("g"))

	ok, err := EncodeBytes("g", make([]byte, MaxPayloadLen("g")))
	uassert.NoError(t, err)
	uassert.Equal(t, MaxLen, len(ok))

	_, err2 := EncodeBytes("g", make([]byte, MaxPayloadLen("g")+1))
	uassert.ErrorIs(t, err2, ErrTooLong)

	// A human-readable part that leaves no room at all.
	uassert.Equal(t, 0, MaxPayloadLen(longHRP()))
	_, err3 := EncodeBytes(longHRP(), []byte{1})
	uassert.ErrorIs(t, err3, ErrTooLong)
}

func longHRP() string {
	s := ""
	for i := 0; i < MaxLen; i++ {
		s += "a"
	}
	return s
}
