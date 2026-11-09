package cobs

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// hex renders a byte string as lowercase hex, so a failing vector prints the
// bytes rather than mojibake.
func hex(s string) string {
	const digits = "0123456789abcdef"
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		if i > 0 {
			b.WriteByte(' ')
		}
		b.WriteByte(digits[s[i]>>4])
		b.WriteByte(digits[s[i]&0x0f])
	}
	return b.String()
}

// rng returns the bytes lo..hi inclusive, the run the paper's long vectors are
// built from.
func rng(lo, hi byte) string {
	var b strings.Builder
	for c := int(lo); c <= int(hi); c++ {
		b.WriteByte(byte(c))
	}
	return b.String()
}

// Table 1 of Cheshire and Baker, "Consistent Overhead Byte Stuffing", all ten
// rows. The last five are the ones that decide whether the group boundary is
// handled lazily: an encoder that closes a full group eagerly produces a
// trailing 01 the paper does not have, and the frames then disagree with every
// other implementation on the wire.
func TestPaperVectors(t *testing.T) {
	cases := []struct {
		name     string
		in, want string
	}{
		{"empty", "", "\x01"},
		{"1: one zero", "\x00", "\x01\x01"},
		{"2: two zeros", "\x00\x00", "\x01\x01\x01"},
		{"3: zero in the middle", "\x11\x22\x00\x33", "\x03\x11\x22\x02\x33"},
		{"4: no zero at all", "\x11\x22\x33\x44", "\x05\x11\x22\x33\x44"},
		{"5: trailing zeros", "\x11\x00\x00\x00", "\x02\x11\x01\x01\x01"},
		{"6: a full group, exactly", rng(0x01, 0xfe), "\xff" + rng(0x01, 0xfe)},
		{"7: zero then a full group", "\x00" + rng(0x01, 0xfe), "\x01\xff" + rng(0x01, 0xfe)},
		{"8: one byte past a full group", rng(0x01, 0xff), "\xff" + rng(0x01, 0xfe) + "\x02\xff"},
		{"9: a full group then a zero", rng(0x02, 0xff) + "\x00", "\xff" + rng(0x02, 0xff) + "\x01\x01"},
		{"10: a zero one short of the boundary", rng(0x03, 0xff) + "\x00\x01", "\xfe" + rng(0x03, 0xff) + "\x02\x01"},
	}
	for _, c := range cases {
		got := Encode(c.in)
		uassert.Equal(t, hex(c.want), hex(got), c.name)

		back, err := Decode(got)
		uassert.NoError(t, err, c.name)
		uassert.Equal(t, hex(c.in), hex(back), c.name)
	}
}

// The point of the codec: whatever goes in, no zero comes out, so a zero is
// free to mean "record ends here".
func TestEncodingNeverContainsTheDelimiter(t *testing.T) {
	for _, in := range []string{"", "\x00", "\x00\x00\x00", rng(0x00, 0xff), rng(0x00, 0xff) + rng(0x00, 0xff)} {
		got := Encode(in)
		uassert.Equal(t, -1, strings.IndexByte(got, Delimiter), hex(got))
		uassert.True(t, len(got) >= 1, hex(got))

		back, err := Decode(got)
		uassert.NoError(t, err)
		uassert.Equal(t, hex(in), hex(back))
	}
}

// The bound is what COBS is for: escape-based stuffing doubles a payload of
// zeros, this adds one byte per 254 and never more.
func TestOverheadStaysBounded(t *testing.T) {
	for _, n := range []int{0, 1, 253, 254, 255, 508, 509, 1000} {
		zeros := strings.Repeat("\x00", n)
		dense := strings.Repeat("\x41", n)

		// All zeros is the input a naive escaper doubles. Here it is the
		// cheapest payload there is: one byte of overhead, at any length,
		// because every group closes before it can fill.
		uassert.Equal(t, n+1, len(Encode(zeros)), "all zeros")

		// The expensive direction is the opposite one, and it is still one
		// code byte per full group and one for the remainder.
		uassert.True(t, len(Encode(dense)) <= MaxEncodedLen(n), "no zeros")
		uassert.True(t, len(Encode(dense))-n <= n/MaxGroup+1, "no zeros")
	}
	uassert.Equal(t, 1, MaxEncodedLen(0))
	uassert.Equal(t, 256, MaxEncodedLen(254))
}

// A zero inside a frame is the one thing that cannot happen, so reading one
// means the frame was cut at the wrong place or corrupted.
func TestDecodeRejectsTheDelimiter(t *testing.T) {
	_, err := Decode("\x03\x11\x00")
	uassert.ErrorIs(t, err, ErrDelimiter)

	_, err = Decode("\x00")
	uassert.ErrorIs(t, err, ErrDelimiter)

	_, err = Decode("\x01\x00\x01")
	uassert.ErrorIs(t, err, ErrDelimiter)
}

// A code byte promising more bytes than the frame holds is truncation, and
// returning the prefix read so far would hand a caller a silently short record.
func TestDecodeRejectsTruncation(t *testing.T) {
	_, err := Decode("\x05\x11\x22")
	uassert.ErrorIs(t, err, ErrTruncated)

	_, err = Decode("\xff" + rng(0x01, 0xfd))
	uassert.ErrorIs(t, err, ErrTruncated)

	_, err = Decode("")
	uassert.ErrorIs(t, err, ErrEmptyFrame)
}

// A one-byte group right after a full group carries neither a payload byte nor
// an implied zero, so it is a second spelling of a payload that already has a
// shorter one. Two spellings of one record is two hashes for one state.
func TestDecodeRejectsNonCanonical(t *testing.T) {
	full := "\xff" + rng(0x01, 0xfe)

	// The shorter spelling is vector 6, and it decodes.
	back, err := Decode(full)
	uassert.NoError(t, err)
	uassert.Equal(t, hex(rng(0x01, 0xfe)), hex(back))

	_, err = Decode(full + "\x01")
	uassert.ErrorIs(t, err, ErrNotCanonical)

	// Two full groups then the same padding.
	_, err = Decode(full + "\xff" + rng(0x01, 0xfe) + "\x01")
	uassert.ErrorIs(t, err, ErrNotCanonical)

	// A one-byte group after a group that was NOT full is vector 1 and 9: it
	// carries the implied zero and must keep decoding.
	back, err = Decode("\x01\x01")
	uassert.NoError(t, err)
	uassert.Equal(t, hex("\x00"), hex(back))
}

// Packing is the reason the codec exists: arbitrary byte records in one
// string, split apart again without a length prefix or an escape pass.
func TestPackRoundTrip(t *testing.T) {
	records := []string{"", "\x00", "hello", "\x00\x00", rng(0x00, 0xff), "tail"}
	packed := Pack(records)
	uassert.Equal(t, len(records), strings.Count(packed, "\x00"))

	back, err := Unpack(packed)
	uassert.NoError(t, err)
	uassert.Equal(t, len(records), len(back))
	for i := range records {
		uassert.Equal(t, hex(records[i]), hex(back[i]))
	}

	// Nothing packed is no records, not one empty record.
	back, err = Unpack("")
	uassert.NoError(t, err)
	uassert.Equal(t, 0, len(back))
	uassert.Equal(t, "", Pack([]string{}))

	// One empty record is a frame, and it is not nothing.
	uassert.Equal(t, hex("\x01\x00"), hex(Pack([]string{""})))
}

// A stream whose last frame has no delimiter is still being written. Decoding
// it would turn a partial record into a complete one.
func TestUnpackRefusesAnUnterminatedTail(t *testing.T) {
	_, err := Unpack(Frame("a") + Encode("b"))
	uassert.ErrorIs(t, err, ErrTruncated)

	_, err = Unpack("\x01")
	uassert.ErrorIs(t, err, ErrTruncated)

	// A delimiter with nothing in front of it is not an empty record.
	_, err = Unpack("\x00")
	uassert.ErrorIs(t, err, ErrEmptyFrame)
}

func TestFrameIsEncodePlusTheDelimiter(t *testing.T) {
	uassert.Equal(t, hex(Encode("hi")+"\x00"), hex(Frame("hi")))
	uassert.Equal(t, hex("\x01\x00"), hex(Frame("")))
}
