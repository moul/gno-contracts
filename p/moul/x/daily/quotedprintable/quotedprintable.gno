// Package quotedprintable implements quoted-printable, the encoding that keeps
// a byte string readable while surviving a transport that only passes printable
// ASCII.
//
// Two rulesets, and they disagree on purpose:
//
//   - [Encode] and [Decode] are RFC 2045 section 6.7, for a body: printable
//     ASCII stays literal, everything else becomes "=XX", and lines are wrapped
//     at 76 columns with a "=\r\n" soft break.
//   - [EncodeWord] and [DecodeWord] are RFC 2047 section 4.2, for a header
//     field: the same "=XX" escape, but a space becomes "_", "?" and "_" are no
//     longer safe, and the whole thing is wrapped in "=?UTF-8?Q?...?=".
//
// Reusing one for the other is the classic quoted-printable bug: a subject line
// run through the body encoder keeps its spaces and its question marks, and the
// receiving parser stops at the first one.
//
// The body encoder is deliberately a BINARY encoder: it treats CR and LF as
// data and writes them as "=0D" and "=0A" rather than as line structure. A
// realm encodes a payload, not an RFC 822 message, and an encoder that rewrote
// line endings on the way through would silently corrupt a signature. Decoding
// still accepts a hard line break from any other encoder and returns it as the
// bytes it stands for, so [Decode]([Encode](s)) == s for every s.
//
// A live demo of this package is at
// [r/moul/x/daily/quotedprintabledemo](/r/moul/x/daily/quotedprintabledemo/v0).
package quotedprintable

import (
	"errors"
	"strings"
)

// MaxLen bounds the input of [Encode] and [EncodeWord] so gas stays
// predictable. [Decode] accepts four times that, which is more than the worst
// case expansion of a MaxLen input.
const MaxLen = 4096

// maxLineLen is RFC 2045's hard limit: no encoded line may exceed 76
// characters, and the soft break's own "=" counts toward it.
const maxLineLen = 76

// maxWordLen is RFC 2047's limit on a single encoded-word, wrapper included.
const maxWordLen = 75

// wordPrefix and wordSuffix wrap an RFC 2047 encoded-word. The charset label is
// fixed: gno strings are UTF-8 and this package transcodes nothing.
const (
	wordPrefix = "=?UTF-8?Q?"
	wordSuffix = "?="
)

const upperhex = "0123456789ABCDEF"

var (
	// ErrTooLong is returned when input exceeds MaxLen.
	ErrTooLong = errors.New("quotedprintable: input too long")
	// ErrCorrupt is returned when input is not valid quoted-printable.
	ErrCorrupt = errors.New("quotedprintable: corrupt input")
	// ErrWordTooLong is returned when an encoded-word would exceed the 75
	// characters RFC 2047 allows. Splitting a long header across several words
	// is the caller's decision, not this package's.
	ErrWordTooLong = errors.New("quotedprintable: encoded-word too long")
	// ErrUnsupportedEncoding is returned for an encoded-word that is not
	// Q-encoded, "B" (base64) above all.
	ErrUnsupportedEncoding = errors.New("quotedprintable: unsupported encoding")
)

// Encode encodes src as a quoted-printable body per RFC 2045 section 6.7,
// wrapped at 76 columns with "=\r\n" soft breaks.
//
// Every byte of src survives: CR and LF are encoded as data, not treated as
// line structure, so the result round-trips through [Decode] exactly.
func Encode(src string) (string, error) {
	if len(src) > MaxLen {
		return "", ErrTooLong
	}
	var b strings.Builder
	line := 0
	for i := 0; i < len(src); i++ {
		c := src[i]
		literal := isLiteral(c)
		if c == ' ' || c == '\t' {
			// A literal space or tab must never be the last character on a
			// line: RFC 2045 lets any transport strip it, and the data would
			// come back short. Keep it literal only while a widest-case token
			// still fits after it on this line, and only when something does
			// in fact follow.
			literal = i+1 < len(src) && line <= maxLineLen-5
		}
		w := 3
		if literal {
			w = 1
		}
		if line+w > maxLineLen-1 {
			b.WriteString("=\r\n")
			line = 0
		}
		if literal {
			b.WriteByte(c)
		} else {
			b.WriteByte('=')
			b.WriteByte(upperhex[c>>4])
			b.WriteByte(upperhex[c&0x0f])
		}
		line += w
	}
	return b.String(), nil
}

// Decode decodes a quoted-printable body.
//
// It is strict where a wrong answer could pass silently: an "=" that is neither
// a soft break nor a valid hex pair is [ErrCorrupt], never a literal "=". It is
// lenient where the intent is unambiguous: lowercase hex is accepted, a bare LF
// counts as a line break, and a byte that should have been encoded is passed
// through rather than refused.
//
// Whitespace at the end of a line is dropped, because RFC 2045 says it cannot
// have been part of the data: whatever added it was a transport, not the sender.
func Decode(s string) (string, error) {
	if len(s) > MaxLen*4 {
		return "", ErrTooLong
	}
	var b strings.Builder
	ws := -1 // start of a run of literal whitespace, held back until it is used
	for i := 0; i < len(s); {
		c := s[i]
		if c == ' ' || c == '\t' {
			if ws < 0 {
				ws = i
			}
			i++
			continue
		}
		if c == '\r' || c == '\n' {
			ws = -1 // trailing whitespace never travelled, so it is not data
			if c == '\r' && i+1 < len(s) && s[i+1] == '\n' {
				b.WriteString("\r\n")
				i += 2
				continue
			}
			b.WriteByte(c)
			i++
			continue
		}
		if ws >= 0 {
			b.WriteString(s[ws:i])
			ws = -1
		}
		if c != '=' {
			b.WriteByte(c)
			i++
			continue
		}
		// A soft line break: "=" then the line ending, both dropped.
		if i+1 < len(s) && s[i+1] == '\n' {
			i += 2
			continue
		}
		if i+2 < len(s) && s[i+1] == '\r' && s[i+2] == '\n' {
			i += 3
			continue
		}
		if i+2 >= len(s) {
			return "", ErrCorrupt
		}
		hi, ok := unhex(s[i+1])
		if !ok {
			return "", ErrCorrupt
		}
		lo, ok := unhex(s[i+2])
		if !ok {
			return "", ErrCorrupt
		}
		b.WriteByte(hi<<4 | lo)
		i += 3
	}
	return b.String(), nil
}

// EncodeWord encodes src as an RFC 2047 Q-encoded word, ready to drop into a
// header field: "=?UTF-8?Q?...?=".
//
// A space becomes "_", and "_", "?" and "=" lose the literal status they have
// in a body. The result is refused with [ErrWordTooLong] past 75 characters
// rather than silently emitting a header no parser is required to accept.
func EncodeWord(src string) (string, error) {
	if len(src) > MaxLen {
		return "", ErrTooLong
	}
	var b strings.Builder
	for i := 0; i < len(src); i++ {
		c := src[i]
		switch {
		case c == ' ':
			b.WriteByte('_')
		case c >= '!' && c <= '~' && c != '=' && c != '?' && c != '_':
			b.WriteByte(c)
		default:
			b.WriteByte('=')
			b.WriteByte(upperhex[c>>4])
			b.WriteByte(upperhex[c&0x0f])
		}
	}
	out := wordPrefix + b.String() + wordSuffix
	if len(out) > maxWordLen {
		return "", ErrWordTooLong
	}
	return out, nil
}

// DecodeWord decodes an RFC 2047 encoded-word.
//
// A string that is not an encoded-word is returned unchanged, which is what a
// header parser wants: most fields are plain text and only some are encoded.
// The charset label is read and ignored, so the bytes come back as they were
// sent; for anything other than UTF-8 or US-ASCII the caller transcodes.
func DecodeWord(s string) (string, error) {
	if len(s) < len(wordPrefix)+len(wordSuffix) ||
		!strings.HasPrefix(s, "=?") || !strings.HasSuffix(s, wordSuffix) {
		return s, nil
	}
	body := s[2 : len(s)-2]
	i := strings.IndexByte(body, '?')
	if i < 0 {
		return "", ErrCorrupt
	}
	rest := body[i+1:]
	j := strings.IndexByte(rest, '?')
	if j < 0 {
		return "", ErrCorrupt
	}
	if enc := rest[:j]; enc != "Q" && enc != "q" {
		return "", ErrUnsupportedEncoding
	}
	text := rest[j+1:]
	var b strings.Builder
	for k := 0; k < len(text); {
		c := text[k]
		switch {
		case c == '_':
			b.WriteByte(' ')
			k++
		case c == ' ' || c == '\t' || c == '\r' || c == '\n':
			// An encoded-word is a single token: whitespace inside it means the
			// header was split and this is not one word.
			return "", ErrCorrupt
		case c == '=':
			if k+2 >= len(text) {
				return "", ErrCorrupt
			}
			hi, ok := unhex(text[k+1])
			if !ok {
				return "", ErrCorrupt
			}
			lo, ok := unhex(text[k+2])
			if !ok {
				return "", ErrCorrupt
			}
			b.WriteByte(hi<<4 | lo)
			k += 3
		default:
			b.WriteByte(c)
			k++
		}
	}
	return b.String(), nil
}

// isLiteral reports whether c may appear as itself in a quoted-printable body:
// printable ASCII other than "=", which always introduces an escape.
func isLiteral(c byte) bool {
	return c >= '!' && c <= '~' && c != '='
}

// unhex returns the value of one hex digit, upper or lower case.
func unhex(c byte) (byte, bool) {
	switch {
	case c >= '0' && c <= '9':
		return c - '0', true
	case c >= 'A' && c <= 'F':
		return c - 'A' + 10, true
	case c >= 'a' && c <= 'f':
		return c - 'a' + 10, true
	}
	return 0, false
}
