// Package varint implements LEB128 / protobuf-style variable-length integers
// over strings, with one deliberate restriction: it only accepts the canonical
// encoding of a value.
//
// A varint stores an integer in base 128, least significant group first. Each
// byte carries seven payload bits and a continuation bit in the high position,
// so values below 128 cost one byte, below 16384 two, and a full uint64 at most
// ten. Signed values go through zigzag first, which interleaves positives and
// negatives so that small magnitudes of either sign stay short.
//
// Live demo: [r/moul/x/daily/varintdemo](/r/moul/x/daily/varintdemo/v0).
package varint

import "errors"

// MaxLen is the longest canonical encoding of a uint64: ten groups of seven
// bits covers 70 bits, which is the first multiple of seven past 64.
const MaxLen = 10

var (
	// ErrTruncated is returned when the input ends inside a varint, meaning
	// the last byte read still had its continuation bit set.
	ErrTruncated = errors.New("varint: truncated")
	// ErrOverflow is returned when the encoded value does not fit in 64 bits.
	ErrOverflow = errors.New("varint: value overflows uint64")
	// ErrNotCanonical is returned for an encoding that is longer than it needs
	// to be, such as a value padded with trailing continuation groups.
	ErrNotCanonical = errors.New("varint: non-canonical encoding")
	// ErrTrailing is returned by the all-at-once decoders when bytes remain
	// after the last complete value.
	ErrTrailing = errors.New("varint: trailing bytes")
)

// PutUvarint returns the canonical encoding of x.
func PutUvarint(x uint64) string {
	return string(AppendUvarint(make([]byte, 0, MaxLen), x))
}

// AppendUvarint appends the encoding of x to dst and returns the extended
// slice, the same shape as Go's encoding/binary.
//
// It takes a byte slice and not a string on purpose: a string accumulator
// copies the whole prefix on every append, which makes packing a sequence
// quadratic in the encoded size. On chain that is gas paid to rebuild bytes
// the caller already had.
func AppendUvarint(dst []byte, x uint64) []byte {
	for x >= 0x80 {
		dst = append(dst, byte(x)|0x80)
		x >>= 7
	}
	return append(dst, byte(x))
}

// PutVarint returns the canonical encoding of x, zigzagged first.
func PutVarint(x int64) string {
	return PutUvarint(ZigZag(x))
}

// AppendVarint appends the zigzagged encoding of x to dst.
func AppendVarint(dst []byte, x int64) []byte {
	return AppendUvarint(dst, ZigZag(x))
}

// Len reports how many bytes PutUvarint(x) would produce, without encoding it.
func Len(x uint64) int {
	n := 1
	for x >= 0x80 {
		x >>= 7
		n++
	}
	return n
}

// LenVarint reports how many bytes PutVarint(x) would produce.
func LenVarint(x int64) int {
	return Len(ZigZag(x))
}

// Uvarint decodes the varint at the start of s and reports how many bytes it
// consumed. The rest of s is ignored, so a stream is read by reslicing.
func Uvarint(s string) (uint64, int, error) {
	var x uint64
	var shift uint
	for i := 0; i < len(s); i++ {
		b := s[i]
		if i == MaxLen-1 {
			// The tenth group may only carry the single bit left over from
			// 63; anything above that, continuation included, overflows.
			if b > 1 {
				return 0, 0, ErrOverflow
			}
		}
		x |= uint64(b&0x7f) << shift
		if b < 0x80 {
			if i > 0 && b == 0 {
				// A zero final group means the value was padded: the same
				// number has a shorter encoding, so this one is not canonical.
				return 0, 0, ErrNotCanonical
			}
			return x, i + 1, nil
		}
		shift += 7
	}
	return 0, 0, ErrTruncated
}

// Varint decodes the zigzagged varint at the start of s.
func Varint(s string) (int64, int, error) {
	u, n, err := Uvarint(s)
	if err != nil {
		return 0, 0, err
	}
	return UnZigZag(u), n, nil
}

// ZigZag maps a signed value onto an unsigned one so that small magnitudes of
// either sign stay small: 0, -1, 1, -2, 2 become 0, 1, 2, 3, 4.
func ZigZag(x int64) uint64 {
	return uint64(x<<1) ^ uint64(x>>63)
}

// UnZigZag is the inverse of [ZigZag].
func UnZigZag(u uint64) int64 {
	return int64(u>>1) ^ -int64(u&1)
}

// PutUvarints encodes every value in xs back to back, into one buffer.
func PutUvarints(xs []uint64) string {
	buf := make([]byte, 0, len(xs)+1)
	for _, x := range xs {
		buf = AppendUvarint(buf, x)
	}
	return string(buf)
}

// Uvarints decodes a string that is nothing but varints. It fails rather than
// returning a partial result: a trailing fragment is corruption, not a value.
func Uvarints(s string) ([]uint64, error) {
	out := []uint64{}
	for len(s) > 0 {
		x, n, err := Uvarint(s)
		if err != nil {
			if err == ErrTruncated {
				return nil, ErrTrailing
			}
			return nil, err
		}
		out = append(out, x)
		s = s[n:]
	}
	return out, nil
}

// PutVarints encodes every value in xs back to back, zigzagged, into one
// buffer.
func PutVarints(xs []int64) string {
	buf := make([]byte, 0, len(xs)+1)
	for _, x := range xs {
		buf = AppendVarint(buf, x)
	}
	return string(buf)
}

// Varints decodes a string that is nothing but zigzagged varints.
func Varints(s string) ([]int64, error) {
	us, err := Uvarints(s)
	if err != nil {
		return nil, err
	}
	out := make([]int64, len(us))
	for i, u := range us {
		out[i] = UnZigZag(u)
	}
	return out, nil
}
