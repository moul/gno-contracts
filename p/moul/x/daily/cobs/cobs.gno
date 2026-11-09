// Package cobs implements Consistent Overhead Byte Stuffing (Cheshire and
// Baker, 1999): it rewrites a payload so that no zero byte survives in it,
// which frees the zero to mean "this record ends here".
//
// The usual way to reach that property is to escape every zero, and that
// doubles a payload made of zeros. COBS instead drops the zeros entirely and
// writes the distances between them: the output is a run of groups, each a
// code byte followed by up to 254 non-zero payload bytes, where the code is
// the group's length plus one and an implied zero sits at the end of any group
// shorter than the maximum. The cost is therefore one byte per 254 bytes of
// payload and never more, whatever the payload contains.
//
// That bound is the whole point. A realm concatenating arbitrary byte records
// into one stored string needs to split them again later, and the two usual
// options are both worse on chain: a length prefix makes the stream unreadable
// from the middle, and an escape pass makes the worst case twice the gas of
// the average one.
//
// Live demo: [r/moul/x/daily/cobsdemo](/r/moul/x/daily/cobsdemo/v0).
package cobs

import "errors"

const (
	// Delimiter is the byte COBS removes from the payload, and therefore the
	// byte a stream is free to use as a record separator.
	Delimiter = 0x00
	// MaxGroup is the most payload bytes one group can carry. A code byte
	// counts its group's length plus one and 0xff is the largest code, so a
	// group holds at most 254 bytes and then has no room for an implied zero.
	MaxGroup = 254
)

var (
	// ErrDelimiter is returned when a zero byte appears inside a frame. It is
	// the one byte the encoding cannot produce, so reading one means the frame
	// was cut at the wrong place or corrupted on the way.
	ErrDelimiter = errors.New("cobs: zero byte inside a frame")
	// ErrTruncated is returned when a code byte promises more payload than the
	// frame holds, or when a packed stream ends without its last delimiter.
	ErrTruncated = errors.New("cobs: frame ends inside a group")
	// ErrNotCanonical is returned for a frame carrying a group that encodes
	// nothing: the same payload has a shorter frame, and two spellings of one
	// record is two hashes for one state.
	ErrNotCanonical = errors.New("cobs: non-canonical encoding")
	// ErrEmptyFrame is returned for a frame with not even a code byte in it.
	// Every payload, the empty one included, encodes to at least one byte.
	ErrEmptyFrame = errors.New("cobs: empty frame")
)

// Encode returns src with every zero byte removed, as one frame. The result
// is never empty and never contains [Delimiter].
func Encode(src string) string {
	return string(AppendEncode(make([]byte, 0, MaxEncodedLen(len(src))), src))
}

// AppendEncode appends the frame for src to dst and returns the extended
// slice, the same shape as the Append helpers in Go's encoding packages.
//
// It takes a byte slice and not a string on purpose: a string accumulator
// copies the whole prefix on every append, which makes packing a sequence
// quadratic in the encoded size. On chain that is gas paid to rebuild bytes
// the caller already had.
func AppendEncode(dst []byte, src string) []byte {
	code := byte(1)
	at := len(dst) // where this group's code byte goes, once the group closes
	dst = append(dst, 0)

	for i := 0; i < len(src); i++ {
		// Closing a full group only when another byte actually arrives is
		// what keeps a payload of exactly 254 non-zero bytes at 255 bytes
		// instead of 256. Closing it eagerly appends a trailing 01 that
		// encodes nothing, which is the shape Decode rejects as
		// non-canonical, and it is the single most common way an
		// implementation ends up disagreeing with every other one.
		if code == 0xff {
			dst[at] = code
			at = len(dst)
			dst = append(dst, 0)
			code = 1
		}
		if src[i] == Delimiter {
			dst[at] = code
			at = len(dst)
			dst = append(dst, 0)
			code = 1
			continue
		}
		dst = append(dst, src[i])
		code++
	}

	dst[at] = code
	return dst
}

// Decode returns the payload of one frame, the inverse of [Encode].
//
// It refuses rather than repairing: a zero byte, a short group and a group
// that encodes nothing all mean the caller is not holding the frame that was
// written, and a partial payload looks exactly like a complete one.
func Decode(src string) (string, error) {
	if len(src) == 0 {
		return "", ErrEmptyFrame
	}

	out := make([]byte, 0, len(src))
	prevFull := false // the group before this one filled its 254 bytes

	for i := 0; i < len(src); {
		code := src[i]
		if code == Delimiter {
			return "", ErrDelimiter
		}
		n := int(code) - 1
		if i+1+n > len(src) {
			return "", ErrTruncated
		}
		for j := 0; j < n; j++ {
			b := src[i+1+j]
			if b == Delimiter {
				return "", ErrDelimiter
			}
			out = append(out, b)
		}
		i += 1 + n

		if i == len(src) {
			// A one-byte group at the very end carries no payload byte, and
			// it only carries the implied zero of the group before it when
			// that group was short enough to have one. After a full group it
			// means nothing at all, so the payload has a shorter frame.
			if prevFull && code == 1 {
				return "", ErrNotCanonical
			}
			break
		}
		if code != 0xff {
			out = append(out, Delimiter)
		}
		prevFull = code == 0xff
	}
	return string(out), nil
}

// MaxEncodedLen reports the longest frame an n-byte payload can produce: one
// code byte per full group, plus one for the group the payload does not fill.
//
// It is an upper bound and not the exact length, which depends on where the
// zeros are. Use it to size a buffer, not to predict a frame.
func MaxEncodedLen(n int) int {
	return n + n/MaxGroup + 1
}

// Frame returns the frame for src followed by [Delimiter], ready to be
// concatenated with others.
func Frame(src string) string {
	return Encode(src) + string([]byte{Delimiter})
}

// Pack frames every record into one string, each one closed by [Delimiter].
// No record may be recovered without [Unpack], but every boundary can be found
// by scanning for a zero, with no parsing and no length table.
func Pack(records []string) string {
	buf := make([]byte, 0, len(records)*2)
	for _, r := range records {
		buf = AppendEncode(buf, r)
		buf = append(buf, Delimiter)
	}
	return string(buf)
}

// Unpack splits a packed stream back into its records.
//
// A stream not ending in a delimiter is one still being written, and decoding
// its tail would turn a partial record into a complete one, so it is refused
// with [ErrTruncated] rather than returning the records before it.
func Unpack(s string) ([]string, error) {
	out := []string{}
	start := 0
	for i := 0; i < len(s); i++ {
		if s[i] != Delimiter {
			continue
		}
		rec, err := Decode(s[start:i])
		if err != nil {
			return nil, err
		}
		out = append(out, rec)
		start = i + 1
	}
	if start != len(s) {
		return nil, ErrTruncated
	}
	return out, nil
}
