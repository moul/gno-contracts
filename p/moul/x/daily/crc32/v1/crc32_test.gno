package crc32

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// Known-answer tests against the published IEEE vectors.
func TestChecksumKnownVectors(t *testing.T) {
	cases := []struct {
		in   string
		want string
	}{
		{"", "00000000"},
		{"a", "e8b7be43"},
		{"abc", "352441c2"},
		{"message digest", "20159d7f"},
		{"abcdefghijklmnopqrstuvwxyz", "4c2750bd"},
		{"123456789", "cbf43926"}, // the standard CRC check value
	}
	for _, c := range cases {
		uassert.Equal(t, c.want, ChecksumHex(c.in))
	}
}

// The classic "check" value: CRC-32/IEEE of "123456789" is 0xCBF43926.
func TestStandardCheckValue(t *testing.T) {
	uassert.Equal(t, uint32(0xCBF43926), Checksum("123456789"))
}

func TestHexIsZeroPadded(t *testing.T) {
	uassert.Equal(t, "00000000", Hex(0))
	uassert.Equal(t, "0000000f", Hex(15))
	uassert.Equal(t, "ffffffff", Hex(0xFFFFFFFF))
	uassert.Equal(t, 8, len(Hex(1)))
}

// A single flipped bit must change the checksum — the entire point.
func TestDetectsSingleBitChange(t *testing.T) {
	base := Checksum("hello world")
	uassert.False(t, base == Checksum("hello worle"))
	uassert.False(t, base == Checksum("Hello world"))
}

// Order matters: a CRC is not a sum.
func TestOrderSensitive(t *testing.T) {
	uassert.False(t, Checksum("ab") == Checksum("ba"))
}

func TestVerify(t *testing.T) {
	uassert.True(t, Verify("abc", 0x352441C2))
	uassert.False(t, Verify("abd", 0x352441C2))
}

// Chaining Update over chunks must equal one shot over the whole message —
// this is why Update takes the raw register rather than a final value.
func TestUpdateIsChunkable(t *testing.T) {
	whole := Checksum("hello world")
	crc := uint32(0xFFFFFFFF)
	crc = Update(crc, ieeeTable, "hello ")
	crc = Update(crc, ieeeTable, "world")
	uassert.Equal(t, whole, Finalize(crc))
}

// Different polynomials must give different answers, and each be stable.
func TestAlternatePolynomials(t *testing.T) {
	c := MakeTable(Castagnoli)
	k := MakeTable(Koopman)
	a := ChecksumWith("123456789", c)
	b := ChecksumWith("123456789", k)
	uassert.False(t, a == Checksum("123456789"))
	uassert.False(t, a == b)
	uassert.Equal(t, a, ChecksumWith("123456789", c)) // stable
}

func TestSplit(t *testing.T) {
	got := Split("a\nabc")
	uassert.Equal(t, 2, len(got))
	uassert.Equal(t, "e8b7be43", got[0])
	uassert.Equal(t, "352441c2", got[1])
}

func TestLongInput(t *testing.T) {
	s := strings.Repeat("gno", 1000)
	uassert.Equal(t, 8, len(ChecksumHex(s)))
	uassert.Equal(t, Checksum(s), Checksum(s))
}
