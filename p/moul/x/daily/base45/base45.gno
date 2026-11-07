// Package base45 implements the base45 encoding of RFC 9285 as a pure,
// reusable package.
//
// Base45 exists for one reason: QR codes have an alphanumeric mode whose
// character set is exactly these 45 characters, and it packs them at 5.5 bits
// each instead of the 8 a byte-mode QR spends. Encoding a payload to base45
// first costs 50% expansion (3 characters per 2 bytes) and still produces a
// smaller QR symbol than feeding the raw bytes in. That is why it carries the
// EU Digital COVID Certificate, which is the deployment everyone has seen.
//
// Two bytes become one 16-bit number written in base 45, and the three
// characters are emitted LEAST significant first, which is the detail that
// catches every reimplementation: "AB" is "BB8", not "8BB". A lone trailing
// byte becomes two characters the same way, so an encoded length is never
// 3n+1 and a decoder must refuse one.
//
// Decoding is strict in both directions a malformed string can be wrong: a
// character outside the alphabet is rejected rather than skipped, and a group
// above 0xFFFF (or a trailing pair above 0xFF) is rejected rather than
// truncated. The alphabet is uppercase, so lowercase input is corrupt input,
// not a case to fold.
//
// A live demo of this package is at
// [r/moul/x/daily/base45demo](/r/moul/x/daily/base45demo/v0).
package base45

import "errors"

// Alphabet is the RFC 9285 §4 character set: the digits, the uppercase
// letters, and nine symbols. Its order is the value order, so the character
// for a digit d is Alphabet[d].
const Alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:"

// MaxLen bounds the input of every function here so gas stays predictable.
const MaxLen = 4096

var (
	// ErrTooLong is returned when input exceeds MaxLen.
	ErrTooLong = errors.New("base45: input too long")
	// ErrCorrupt is returned for a character outside the alphabet, or for a
	// length no encoder can produce.
	ErrCorrupt = errors.New("base45: corrupt input")
	// ErrOverflow is returned when a group decodes above the range its byte
	// count can hold: 0xFFFF for three characters, 0xFF for two.
	ErrOverflow = errors.New("base45: group out of range")
)

// EncodedLen returns the number of characters Encode produces for n bytes.
func EncodedLen(n int) int {
	return n/2*3 + n%2*2
}

// Encode encodes src as base45.
func Encode(src string) (string, error) {
	return EncodeBytes([]byte(src))
}

// EncodeBytes encodes src as base45.
func EncodeBytes(src []byte) (string, error) {
	if len(src) > MaxLen {
		return "", ErrTooLong
	}
	out := make([]byte, 0, EncodedLen(len(src)))
	i := 0
	for ; i+1 < len(src); i += 2 {
		// Two bytes are one 16-bit number, written in base 45 over three
		// characters, least significant first.
		n := int(src[i])<<8 | int(src[i+1])
		out = append(out, Alphabet[n%45], Alphabet[n/45%45], Alphabet[n/2025])
	}
	if i < len(src) {
		// A lone trailing byte is at most 255, so two characters hold it.
		n := int(src[i])
		out = append(out, Alphabet[n%45], Alphabet[n/45])
	}
	return string(out), nil
}

// Decode decodes a base45 string.
func Decode(s string) (string, error) {
	b, err := DecodeBytes(s)
	if err != nil {
		return "", err
	}
	return string(b), nil
}

// DecodeBytes decodes a base45 string.
func DecodeBytes(s string) ([]byte, error) {
	if len(s) > MaxLen {
		return nil, ErrTooLong
	}
	if len(s)%3 == 1 {
		// Groups are three characters and the odd trailing byte is two, so
		// no encoder ever emitted this length.
		return nil, ErrCorrupt
	}
	out := make([]byte, 0, len(s)/3*2+len(s)%3/2)
	i := 0
	for ; i+2 < len(s); i += 3 {
		a, err := digit(s[i])
		if err != nil {
			return nil, err
		}
		b, err := digit(s[i+1])
		if err != nil {
			return nil, err
		}
		c, err := digit(s[i+2])
		if err != nil {
			return nil, err
		}
		n := a + b*45 + c*2025
		if n > 0xFFFF {
			return nil, ErrOverflow
		}
		out = append(out, byte(n>>8), byte(n))
	}
	if i < len(s) {
		a, err := digit(s[i])
		if err != nil {
			return nil, err
		}
		b, err := digit(s[i+1])
		if err != nil {
			return nil, err
		}
		n := a + b*45
		if n > 0xFF {
			return nil, ErrOverflow
		}
		out = append(out, byte(n))
	}
	return out, nil
}

// digit maps one character to its value, or reports it as corrupt. The
// alphabet is small and unordered past 'Z', so this is a scan rather than
// arithmetic on the byte.
func digit(c byte) (int, error) {
	for i := 0; i < len(Alphabet); i++ {
		if Alphabet[i] == c {
			return i, nil
		}
	}
	return 0, ErrCorrupt
}
