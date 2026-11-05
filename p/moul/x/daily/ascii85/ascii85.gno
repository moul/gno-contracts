// Package ascii85 implements the Adobe/btoa ascii85 binary-to-text encoding as
// a pure, reusable package.
//
// Four bytes become five printable characters drawn from '!' to 'u', so the
// encoding costs 25% expansion against base64's 33% and hex's 100%. That is the
// entire reason to reach for it: the same bytes, a fifth smaller than base64,
// at the price of an alphabet that is not URL-safe and not case-insensitive.
//
// Two shapes are produced. Encode returns the bare character stream, which is
// what a length-prefixed container wants. EncodeFramed wraps it in the Adobe
// "<~" and "~>" delimiters, which is what a PostScript or PDF stream carries,
// and Decode accepts either.
//
// # It refuses the group Go's encoder silently wraps
//
// A five-character group is a base-85 numeral and only values below 2^32 name
// four bytes, yet nothing in the character set stops a stream from spelling a
// larger one. encoding/ascii85 in the Go standard library computes the group in
// a uint32 and lets it wrap: "s8W-\"" is 2^32 exactly and decodes there to four
// zero bytes, the same answer as the single character "z", and "uuuuu" decodes
// to four bytes that appear nowhere in the input. Measured against Go 1.x on
// 2026-11-05.
//
// Two different texts decoding to the same bytes is a forgery primitive wherever
// the text is what gets signed, compared or used as a key, so Decode returns
// [ErrOverflow] instead. It is the one deliberate incompatibility here.
//
// A live demo of this package is at
// [r/moul/x/daily/ascii85demo](/r/moul/x/daily/ascii85demo/v0).
package ascii85

import (
	"errors"
	"strings"
)

// Framing delimiters, as Adobe writes them around a stream.
const (
	FramePrefix = "<~"
	FrameSuffix = "~>"
)

// MaxLen bounds the bytes [Encode] accepts, so gas stays predictable.
const MaxLen = 4096

// MaxTextLen bounds the characters [Decode] reads. It is MaxLen expanded by a
// quarter, plus the two delimiters, plus room for the line break every 72
// characters that a PostScript stream carries.
const MaxTextLen = 5300

var (
	// ErrTooLong is returned when input exceeds [MaxLen] or [MaxTextLen].
	ErrTooLong = errors.New("ascii85: input too long")
	// ErrCorrupt is returned when input is not valid ascii85.
	ErrCorrupt = errors.New("ascii85: corrupt input")
	// ErrOverflow is returned when a group names a value of 2^32 or more,
	// which no four bytes can produce.
	ErrOverflow = errors.New("ascii85: group overflows 32 bits")
)

// Encode encodes src as bare ascii85, with no delimiters.
//
// Four bytes become five characters. A final group of one, two or three bytes
// becomes two, three or four characters: the group is zero-padded to four bytes
// and the padding characters are dropped, which is what makes the encoding
// length-preserving without a pad character. Four zero bytes become the single
// character "z", so the output is not a fixed ratio of the input.
func Encode(src string) (string, error) {
	if len(src) > MaxLen {
		return "", ErrTooLong
	}
	var b strings.Builder
	for i := 0; i < len(src); i += 4 {
		n := len(src) - i
		if n > 4 {
			n = 4
		}
		var v uint32
		for j := 0; j < 4; j++ {
			v <<= 8
			if j < n {
				v |= uint32(src[i+j])
			}
		}
		if v == 0 && n == 4 {
			b.WriteByte('z')
			continue
		}
		var chars [5]byte
		for j := 4; j >= 0; j-- {
			chars[j] = byte(v%85) + '!'
			v /= 85
		}
		for j := 0; j <= n; j++ {
			b.WriteByte(chars[j])
		}
	}
	return b.String(), nil
}

// EncodeFramed encodes src and wraps it in the Adobe delimiters.
func EncodeFramed(src string) (string, error) {
	enc, err := Encode(src)
	if err != nil {
		return "", err
	}
	return FramePrefix + enc + FrameSuffix, nil
}

// Decode decodes bare or framed ascii85.
//
// Whitespace between characters is ignored, because the encoding is written to
// be wrapped at a line width. The delimiters are optional but balanced: a
// closing "~>" with no opening "<~" is [ErrCorrupt] rather than a stream that
// happens to end in two punctuation characters.
//
// A group naming 2^32 or more is [ErrOverflow]. See the package comment for why
// that is a refusal here and a silent wrap in Go's standard library.
func Decode(text string) (string, error) {
	if len(text) > MaxTextLen {
		return "", ErrTooLong
	}
	s := strings.TrimSpace(text)
	if strings.HasPrefix(s, FramePrefix) {
		if !strings.HasSuffix(s, FrameSuffix) || len(s) < len(FramePrefix)+len(FrameSuffix) {
			return "", ErrCorrupt
		}
		s = s[len(FramePrefix) : len(s)-len(FrameSuffix)]
	}
	if strings.Contains(s, FrameSuffix) || strings.Contains(s, FramePrefix) {
		return "", ErrCorrupt
	}

	var out strings.Builder
	var group [5]byte
	n := 0
	for i := 0; i < len(s); i++ {
		c := s[i]
		if isSpace(c) {
			continue
		}
		if c == 'z' {
			// The shortcut stands for a whole group, so it cannot
			// appear once one has been started.
			if n != 0 {
				return "", ErrCorrupt
			}
			out.WriteString("\x00\x00\x00\x00")
			continue
		}
		if c < '!' || c > 'u' {
			return "", ErrCorrupt
		}
		group[n] = c
		n++
		if n == 5 {
			if err := emit(&out, group, 4); err != nil {
				return "", err
			}
			n = 0
		}
	}
	switch n {
	case 0:
	case 1:
		// One character carries fewer than eight bits, so no byte can
		// have produced it.
		return "", ErrCorrupt
	default:
		// Pad with the largest digit: the dropped bytes round up to
		// what the encoder discarded, so the kept ones come back exact.
		for j := n; j < 5; j++ {
			group[j] = 'u'
		}
		if err := emit(&out, group, n-1); err != nil {
			return "", err
		}
	}
	return out.String(), nil
}

// emit writes the first keep bytes of a decoded group.
func emit(out *strings.Builder, group [5]byte, keep int) error {
	// uint64 so the sum is observed rather than wrapped.
	var v uint64
	for j := 0; j < 5; j++ {
		v = v*85 + uint64(group[j]-'!')
	}
	if v > 0xFFFFFFFF {
		return ErrOverflow
	}
	for j := 0; j < keep; j++ {
		out.WriteByte(byte(v >> uint(24-8*j)))
	}
	return nil
}

// isSpace reports whether c is whitespace an encoder may have inserted.
func isSpace(c byte) bool {
	return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\v' || c == '\f'
}
