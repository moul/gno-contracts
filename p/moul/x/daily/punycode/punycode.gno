// Package punycode implements RFC 3492 punycode, the bootstring encoding that
// turns a unicode string into the ASCII subset a DNS label is allowed to carry.
//
// It is the reason an address bar can hold `bücher.example` while the wire
// carries `xn--bcher-kva.example`. The interesting property is that the
// encoding is not a cipher over bytes: it writes out every basic (ASCII)
// character first, verbatim, then appends a compressed description of where the
// non-basic ones were inserted. So an all-ASCII string encodes to itself plus a
// delimiter, and a mostly-ASCII string stays mostly readable.
//
// Two layers, because callers want different ones:
//
//   - [Encode] and [Decode] are the raw codec, one label at a time, no prefix.
//   - [EncodeDomain] and [DecodeDomain] apply it per dot-separated label and
//     manage the `xn--` ACE prefix, which is what a domain name actually uses.
//
// Decoding is total and bounded: every ASCII input returns a value or an error,
// never a panic and never an unbounded loop, because a realm that renders a
// user-supplied label cannot afford either.
//
// What this is NOT: nameprep/IDNA2008. There is no case folding, no
// normalization, no confusable or bidi checking. `EncodeDomain` encodes what it
// is given. Do not use it to decide that two domain names are the same.
//
// A live demo of this package is at
// [r/moul/x/daily/punycodedemo](/r/moul/x/daily/punycodedemo/v0).
package punycode

import (
	"errors"
	"strings"
)

// The RFC 3492 section 5 bootstring parameters for punycode. They are not
// tunable here: changing one produces an encoding nothing else can read.
const (
	base        = 36
	tmin        = 1
	tmax        = 26
	skew        = 38
	damp        = 700
	initialBias = 72
	initialN    = 128 // the first non-basic code point
	delimiter   = '-'
)

// ACEPrefix marks a domain label as punycode-encoded.
const ACEPrefix = "xn--"

// MaxLen bounds input so gas stays predictable. A DNS label is 63 bytes and a
// full name 253, so this is generous for the real use and still a hard stop.
const MaxLen = 1024

// maxRune is the largest valid unicode code point.
const maxRune = 0x10FFFF

// maxDelta bounds the bootstring accumulator. A legitimate value never exceeds
// maxRune*(MaxLen+1), about 1.1e9; anything past this cap is a crafted input,
// and stopping here is what keeps the arithmetic below inside int.
const maxDelta = 1 << 40

var (
	// ErrTooLong is returned when input exceeds MaxLen.
	ErrTooLong = errors.New("punycode: input too long")
	// ErrInvalid is returned for input that is not valid punycode: a non-ASCII
	// byte, a character that is not a bootstring digit, or a truncated number.
	ErrInvalid = errors.New("punycode: invalid input")
	// ErrOverflow is returned when a decode describes a code point outside the
	// unicode range, which only a crafted input does.
	ErrOverflow = errors.New("punycode: overflow")
)

// adapt is the RFC 3492 section 6.1 bias adaptation. It is what keeps the digit
// count small for the common case of a string whose non-basic code points are
// clustered in one script: after the first one, the next ones are cheap.
func adapt(delta, numPoints int, firstTime bool) int {
	if firstTime {
		delta /= damp
	} else {
		delta /= 2
	}
	delta += delta / numPoints
	k := 0
	for delta > ((base-tmin)*tmax)/2 {
		delta /= base - tmin
		k += base
	}
	return k + ((base-tmin+1)*delta)/(delta+skew)
}

// threshold is t(k) from section 6.1, clamped into [tmin, tmax].
func threshold(k, bias int) int {
	t := k - bias
	if t < tmin {
		return tmin
	}
	if t > tmax {
		return tmax
	}
	return t
}

// encodeDigit maps 0..35 to the bootstring alphabet: a-z then 0-9. Output is
// always lowercase; the RFC's uppercase flag carries case information that a
// domain label does not need.
func encodeDigit(d int) byte {
	if d < 26 {
		return byte('a' + d)
	}
	return byte('0' + d - 26)
}

// decodeDigit maps a bootstring character to 0..35, or -1. Uppercase is
// rejected rather than folded: an encoder here never emits it, and accepting it
// would make two spellings decode to the same label.
func decodeDigit(c byte) int {
	switch {
	case c >= 'a' && c <= 'z':
		return int(c - 'a')
	case c >= '0' && c <= '9':
		return int(c-'0') + 26
	}
	return -1
}

// Encode returns the punycode of s, without any ACE prefix.
//
// An all-ASCII string encodes to itself followed by the delimiter: Encode("abc")
// is "abc-", not "abc". The delimiter is not decoration, it is what tells the
// decoder where the verbatim part ends.
func Encode(s string) (string, error) {
	if len(s) > MaxLen {
		return "", ErrTooLong
	}
	input := []rune(s)

	var b strings.Builder
	basic := 0
	for _, r := range input {
		if r < initialN {
			b.WriteByte(byte(r))
			basic++
		}
	}
	if basic > 0 {
		b.WriteByte(delimiter)
	}

	h := basic
	n := rune(initialN)
	delta := 0
	bias := initialBias

	for h < len(input) {
		// the smallest non-basic code point still to be placed
		m := rune(maxRune + 1)
		for _, r := range input {
			if r >= n && r < m {
				m = r
			}
		}
		if m > maxRune {
			return "", ErrInvalid // a rune outside unicode, only from bad input
		}

		delta += int(m-n) * (h + 1)
		if delta > maxDelta {
			return "", ErrOverflow
		}
		n = m

		for _, r := range input {
			if r < n {
				delta++
			}
			if r != n {
				continue
			}
			q := delta
			for k := base; ; k += base {
				t := threshold(k, bias)
				if q < t {
					break
				}
				b.WriteByte(encodeDigit(t + (q-t)%(base-t)))
				q = (q - t) / (base - t)
			}
			b.WriteByte(encodeDigit(q))
			bias = adapt(delta, h+1, h == basic)
			delta = 0
			h++
		}
		delta++
		n++
	}
	return b.String(), nil
}

// Decode parses punycode back into a unicode string. It expects no ACE prefix.
//
// Every failure mode returns an error: a non-ASCII byte, a character outside
// the bootstring alphabet, a number that ends mid-sequence, and a delta that
// describes a code point outside unicode.
func Decode(s string) (string, error) {
	if len(s) > MaxLen {
		return "", ErrTooLong
	}
	for i := 0; i < len(s); i++ {
		if s[i] >= initialN {
			return "", ErrInvalid
		}
	}

	var output []rune
	start := 0
	// Everything before the LAST delimiter is literal. The last one, not the
	// first: a literal part may itself contain delimiters, which is how
	// "-> $1.00 <-" survives the round trip.
	if pos := strings.LastIndexByte(s, delimiter); pos > 0 {
		for i := 0; i < pos; i++ {
			output = append(output, rune(s[i]))
		}
		start = pos + 1
	}

	n := rune(initialN)
	i := 0
	bias := initialBias

	for p := start; p < len(s); {
		oldi := i
		w := 1
		for k := base; ; k += base {
			if p >= len(s) {
				return "", ErrInvalid // the number ran off the end
			}
			digit := decodeDigit(s[p])
			p++
			if digit < 0 {
				return "", ErrInvalid
			}
			i += digit * w
			if i > maxDelta {
				return "", ErrOverflow
			}
			t := threshold(k, bias)
			if digit < t {
				break
			}
			w *= base - t
			if w > maxDelta {
				return "", ErrOverflow
			}
		}

		points := len(output) + 1
		bias = adapt(i-oldi, points, oldi == 0)
		n += rune(i / points)
		if n > maxRune || n < 0 {
			return "", ErrOverflow
		}
		i %= points

		// insert n at position i
		output = append(output, 0)
		copy(output[i+1:], output[i:])
		output[i] = n
		i++
	}
	return string(output), nil
}

// EncodeDomain applies punycode per dot-separated label, prefixing each label
// that needed it with "xn--" and leaving every all-ASCII label untouched.
//
// Leaving ASCII labels alone is what makes this idempotent: running it twice
// gives the same answer, because the second pass sees only ASCII.
func EncodeDomain(name string) (string, error) {
	if len(name) > MaxLen {
		return "", ErrTooLong
	}
	labels := strings.Split(name, ".")
	for i, label := range labels {
		if isASCII(label) {
			continue
		}
		enc, err := Encode(label)
		if err != nil {
			return "", err
		}
		labels[i] = ACEPrefix + enc
	}
	return strings.Join(labels, "."), nil
}

// DecodeDomain reverses [EncodeDomain]: every "xn--" label is decoded, every
// other label is passed through.
func DecodeDomain(name string) (string, error) {
	if len(name) > MaxLen {
		return "", ErrTooLong
	}
	labels := strings.Split(name, ".")
	for i, label := range labels {
		if !strings.HasPrefix(label, ACEPrefix) {
			continue
		}
		dec, err := Decode(label[len(ACEPrefix):])
		if err != nil {
			return "", err
		}
		labels[i] = dec
	}
	return strings.Join(labels, "."), nil
}

// isASCII reports whether s is entirely basic code points.
func isASCII(s string) bool {
	for i := 0; i < len(s); i++ {
		if s[i] >= initialN {
			return false
		}
	}
	return true
}
