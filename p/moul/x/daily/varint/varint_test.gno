package varint

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

const (
	minInt64  = -1 << 63
	maxInt64  = 1<<63 - 1
	maxUint64 = 1<<64 - 1
)

// hex renders a byte string as lowercase hex, so a failing vector prints the
// bytes rather than mojibake.
func hex(s string) string {
	const digits = "0123456789abcdef"
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		b.WriteByte(digits[s[i]>>4])
		b.WriteByte(digits[s[i]&0x0f])
	}
	return b.String()
}

// The protobuf base-128 vectors, one per group boundary plus the documented
// 300 example and the full 64-bit maximum.
func TestUvarintVectors(t *testing.T) {
	cases := []struct {
		in   uint64
		want string
	}{
		{0, "00"},
		{1, "01"},
		{127, "7f"},
		{128, "8001"},
		{300, "ac02"},
		{16383, "ff7f"},
		{16384, "808001"},
		{maxUint64, "ffffffffffffffffff01"},
	}
	for _, c := range cases {
		got := PutUvarint(c.in)
		uassert.Equal(t, c.want, hex(got))

		back, n, err := Uvarint(got)
		uassert.NoError(t, err)
		uassert.Equal(t, c.in, back)
		uassert.Equal(t, len(got), n)
	}
}

func TestLenAgreesWithEncoding(t *testing.T) {
	for _, x := range []uint64{0, 1, 127, 128, 16383, 16384, 2097151, 2097152, maxUint64} {
		uassert.Equal(t, len(PutUvarint(x)), Len(x))
	}
	// The boundary is what the groups are for: one byte up to 127.
	uassert.Equal(t, 1, Len(127))
	uassert.Equal(t, 2, Len(128))
	uassert.Equal(t, MaxLen, Len(maxUint64))
}

func TestZigZagVectors(t *testing.T) {
	cases := []struct {
		in   int64
		want uint64
	}{
		{0, 0},
		{-1, 1},
		{1, 2},
		{-2, 3},
		{2, 4},
		{maxInt64, maxUint64 - 1},
		{minInt64, maxUint64},
	}
	for _, c := range cases {
		uassert.Equal(t, c.want, ZigZag(c.in))
		uassert.Equal(t, c.in, UnZigZag(c.want))
	}
}

func TestVarintRoundTrip(t *testing.T) {
	for _, x := range []int64{0, -1, 1, -64, 63, -1000000, 1000000, minInt64, maxInt64} {
		enc := PutVarint(x)
		uassert.Equal(t, len(enc), LenVarint(x))

		back, n, err := Varint(enc)
		uassert.NoError(t, err)
		uassert.Equal(t, x, back)
		uassert.Equal(t, len(enc), n)
	}
}

// Zigzag is the whole reason signed values are not encoded directly: -1 as a
// two's complement uint64 is ten bytes, as a zigzag it is one.
func TestZigZagKeepsSmallNegativesShort(t *testing.T) {
	uassert.Equal(t, 1, LenVarint(-1))
	uassert.Equal(t, 1, LenVarint(-64))
	uassert.Equal(t, 2, LenVarint(-65))
	uassert.Equal(t, MaxLen, Len(uint64(0xffffffffffffffff))) // the same -1, unzigzagged
}

func TestRejectsNonCanonical(t *testing.T) {
	cases := []struct {
		name, in string
	}{
		{"zero padded once", "\x80\x00"},
		{"one padded once", "\x81\x00"},
		{"zero padded thrice", "\x80\x80\x80\x00"},
		{"full width padding", "\xff\xff\xff\xff\xff\xff\xff\xff\xff\x00"},
	}
	for _, c := range cases {
		_, _, err := Uvarint(c.in)
		uassert.ErrorIs(t, err, ErrNotCanonical)
	}
	// A single zero byte is canonical: it is the only encoding of 0.
	x, n, err := Uvarint("\x00")
	uassert.NoError(t, err)
	uassert.Equal(t, uint64(0), x)
	uassert.Equal(t, 1, n)
}

func TestRejectsTruncated(t *testing.T) {
	for _, s := range []string{"", "\x80", "\xff\xff", strings.Repeat("\xff", 9)} {
		_, _, err := Uvarint(s)
		uassert.ErrorIs(t, err, ErrTruncated)
	}
}

func TestRejectsOverflow(t *testing.T) {
	// Ten groups carry 70 bits; the tenth may only hold the one bit left of 64.
	_, _, err := Uvarint(strings.Repeat("\xff", 9) + "\x02")
	uassert.ErrorIs(t, err, ErrOverflow)

	// An eleventh group is unreachable, so it reads as overflow too.
	_, _, err = Uvarint(strings.Repeat("\xff", 10) + "\x01")
	uassert.ErrorIs(t, err, ErrOverflow)

	// Exactly at the limit is fine.
	x, n, err := Uvarint(strings.Repeat("\xff", 9) + "\x01")
	uassert.NoError(t, err)
	uassert.Equal(t, uint64(maxUint64), x)
	uassert.Equal(t, MaxLen, n)
}

func TestUvarintReadsOnlyItsOwnPrefix(t *testing.T) {
	s := PutUvarint(300) + PutUvarint(1) + "leftover"
	x, n, err := Uvarint(s)
	uassert.NoError(t, err)
	uassert.Equal(t, uint64(300), x)
	uassert.Equal(t, 2, n)

	x, n, err = Uvarint(s[n:])
	uassert.NoError(t, err)
	uassert.Equal(t, uint64(1), x)
	uassert.Equal(t, 1, n)
}

func TestSequences(t *testing.T) {
	in := []uint64{0, 1, 127, 128, 300, maxUint64}
	enc := PutUvarints(in)
	uassert.Equal(t, 1+1+1+2+2+10, len(enc))

	out, err := Uvarints(enc)
	uassert.NoError(t, err)
	uassert.Equal(t, len(in), len(out))
	for i := range in {
		uassert.Equal(t, in[i], out[i])
	}

	signed := []int64{0, -1, 1, minInt64, maxInt64}
	back, err := Varints(PutVarints(signed))
	uassert.NoError(t, err)
	uassert.Equal(t, len(signed), len(back))
	for i := range signed {
		uassert.Equal(t, signed[i], back[i])
	}
}

// A partial value at the end is corruption, and returning the values read so
// far would hand a caller a silently short list.
func TestSequenceRefusesTrailingFragment(t *testing.T) {
	_, err := Uvarints(PutUvarint(300) + "\x80")
	uassert.ErrorIs(t, err, ErrTrailing)

	_, err = Varints(PutVarint(-5) + "\xff")
	uassert.ErrorIs(t, err, ErrTrailing)

	out, err := Uvarints("")
	uassert.NoError(t, err)
	uassert.Equal(t, 0, len(out))
}

func TestAppendBuildsInPlace(t *testing.T) {
	var buf []byte
	buf = AppendUvarint(buf, 300)
	buf = AppendVarint(buf, -1)
	uassert.Equal(t, "ac0201", hex(string(buf)))
}
