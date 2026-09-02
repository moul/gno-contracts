// Package base32 implements RFC 4648 base32 and Crockford base32 as a pure,
// reusable package.
//
// Two alphabets, for two different jobs:
//
//   - RFC 4648 (A–Z, 2–7) with '=' padding — the interoperable one; use it when
//     something else has to decode the result.
//   - Crockford (0–9, A–Z minus I, L, O and U) — designed to be read aloud and
//     typed by humans: decoding folds case, treats I/L as 1 and O as 0, and
//     ignores hyphens, so a mis-heard identifier still decodes. U is excluded
//     to avoid accidental obscenities.
//
// Base32 costs 60% expansion (8 characters per 5 bytes) versus base64's 33%.
// You take that hit to get an alphabet that survives case-insensitive systems
// and being read over the phone.
//
// A live demo of this package is at
// [r/moul/x/daily/base32demo](/r/moul/x/daily/base32demo/v1).
package base32

import (
	"errors"
	"strings"
)

// Alphabets.
const (
	StdAlphabet       = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
	CrockfordAlphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
)

// MaxLen bounds input so gas stays predictable.
const MaxLen = 4096

var (
	// ErrTooLong is returned when input exceeds MaxLen.
	ErrTooLong = errors.New("base32: input too long")
	// ErrCorrupt is returned when input is not valid base32.
	ErrCorrupt = errors.New("base32: corrupt input")
)

// encode turns src into base32 over the given alphabet, padding when pad.
func encode(src, alphabet string, pad bool) (string, error) {
	if len(src) > MaxLen {
		return "", ErrTooLong
	}
	var b strings.Builder
	for i := 0; i < len(src); i += 5 {
		// gather up to 5 bytes into a 40-bit group
		var buf [5]byte
		n := 0
		for j := 0; j < 5 && i+j < len(src); j++ {
			buf[j] = src[i+j]
			n++
		}
		// 5 bytes -> 8 characters of 5 bits
		var chars [8]byte
		chars[0] = buf[0] >> 3
		chars[1] = (buf[0]&0x07)<<2 | buf[1]>>6
		chars[2] = (buf[1] & 0x3E) >> 1
		chars[3] = (buf[1]&0x01)<<4 | buf[2]>>4
		chars[4] = (buf[2]&0x0F)<<1 | buf[3]>>7
		chars[5] = (buf[3] & 0x7C) >> 2
		chars[6] = (buf[3]&0x03)<<3 | buf[4]>>5
		chars[7] = buf[4] & 0x1F

		// how many characters this group actually carries
		out := [6]int{0, 2, 4, 5, 7, 8}[n]
		for j := 0; j < out; j++ {
			b.WriteByte(alphabet[chars[j]])
		}
		if pad {
			for j := out; j < 8; j++ {
				b.WriteByte('=')
			}
		}
	}
	return b.String(), nil
}

// Encode returns the RFC 4648 base32 of src, with '=' padding.
func Encode(src string) (string, error) { return encode(src, StdAlphabet, true) }

// EncodeUnpadded returns RFC 4648 base32 without padding.
func EncodeUnpadded(src string) (string, error) { return encode(src, StdAlphabet, false) }

// EncodeCrockford returns Crockford base32, which is never padded.
func EncodeCrockford(src string) (string, error) { return encode(src, CrockfordAlphabet, false) }

// stdValue maps an RFC 4648 character to its 5-bit value, or -1.
func stdValue(c byte) int {
	switch {
	case c >= 'A' && c <= 'Z':
		return int(c - 'A')
	case c >= 'a' && c <= 'z':
		return int(c - 'a') // tolerate lowercase on decode
	case c >= '2' && c <= '7':
		return int(c-'2') + 26
	}
	return -1
}

// crockfordValue maps a Crockford character to its value, or -1.
//
// The forgiving part: case is folded, I and L read as 1, O reads as 0, and
// hyphens are skipped by the caller. This is what makes a Crockford identifier
// survive being written down and typed back in.
func crockfordValue(c byte) int {
	if c >= 'a' && c <= 'z' {
		c -= 32
	}
	switch c {
	case 'O':
		return 0
	case 'I', 'L':
		return 1
	}
	if c >= '0' && c <= '9' {
		return int(c - '0')
	}
	if c >= 'A' && c <= 'Z' {
		if i := strings.IndexByte(CrockfordAlphabet, c); i >= 0 {
			return i
		}
	}
	return -1
}

// decode turns base32 back into bytes using the given value function.
func decode(s string, value func(byte) int, skipHyphen bool) (string, error) {
	if len(s) > MaxLen {
		return "", ErrTooLong
	}
	// strip padding and (for Crockford) hyphens
	var clean strings.Builder
	for i := 0; i < len(s); i++ {
		c := s[i]
		if c == '=' {
			continue
		}
		if skipHyphen && c == '-' {
			continue
		}
		clean.WriteByte(c)
	}
	in := clean.String()

	var b strings.Builder
	var acc uint64
	bits := 0
	for i := 0; i < len(in); i++ {
		v := value(in[i])
		if v < 0 {
			return "", ErrCorrupt
		}
		acc = acc<<5 | uint64(v)
		bits += 5
		if bits >= 8 {
			bits -= 8
			b.WriteByte(byte(acc >> uint(bits)))
			acc &= (1 << uint(bits)) - 1
		}
	}
	// leftover bits must be zero padding, never data
	if bits >= 5 || acc != 0 {
		return "", ErrCorrupt
	}
	return b.String(), nil
}

// Decode parses RFC 4648 base32, tolerating lowercase and missing padding.
func Decode(s string) (string, error) { return decode(s, stdValue, false) }

// DecodeCrockford parses Crockford base32, folding case, reading I/L as 1 and
// O as 0, and ignoring hyphens.
func DecodeCrockford(s string) (string, error) { return decode(s, crockfordValue, true) }
