// Package hexdump renders bytes in the classic xxd/hexdump -C layout, as a
// pure, reusable package.
//
// The format is the familiar one: an 8-digit hex offset, then 16 bytes as hex
// in two 8-byte groups separated by an extra space, then the same bytes as
// ASCII between pipes with non-printables shown as ".". Short final lines are
// padded so the ASCII column stays aligned — the whole point of the layout.
//
// Useful on chain for exactly the reason it is useful off it: when a value is
// not what you expected, the bytes tell you why. Encoding bugs, stray NULs,
// UTF-8 that is not what it claims, trailing whitespace — all invisible in a
// rendered string and obvious in a dump.
//
// A live demo of this package is at
// [r/moul/x/daily/hexdumpdemo](/r/moul/x/daily/hexdumpdemo/v1).
package hexdump

import "strings"

// MaxBytes bounds a dump so gas stays predictable. Input beyond this is
// truncated and reported by Dump's second return value.
const MaxBytes = 4096

// BytesPerLine is the classic 16.
const BytesPerLine = 16

const hexDigits = "0123456789abcdef"

// Dump renders b in the xxd -C layout. It returns the dump and the number of
// bytes rendered, which is less than len(b) when the input exceeds MaxBytes.
func Dump(b []byte) (string, int) {
	n := len(b)
	if n > MaxBytes {
		n = MaxBytes
	}
	if n == 0 {
		return "", 0
	}

	var sb strings.Builder
	for off := 0; off < n; off += BytesPerLine {
		end := off + BytesPerLine
		if end > n {
			end = n
		}
		sb.WriteString(Line(off, b[off:end]))
		sb.WriteString("\n")
	}
	return sb.String(), n
}

// DumpString is Dump over a string's bytes.
func DumpString(s string) (string, int) { return Dump([]byte(s)) }

// Line renders one line: offset, hex columns, ASCII gutter. chunk must hold at
// most BytesPerLine bytes; a shorter chunk is padded so columns stay aligned.
func Line(offset int, chunk []byte) string {
	var sb strings.Builder
	sb.WriteString(Offset(offset))
	sb.WriteString("  ")

	for i := 0; i < BytesPerLine; i++ {
		if i == BytesPerLine/2 {
			sb.WriteString(" ") // the classic gap between the two 8-byte groups
		}
		if i < len(chunk) {
			sb.WriteString(Hex(chunk[i]))
		} else {
			sb.WriteString("  ") // pad so the ASCII gutter never shifts
		}
		sb.WriteString(" ")
	}

	sb.WriteString(" |")
	sb.WriteString(ASCII(chunk))
	sb.WriteString("|")
	return sb.String()
}

// Offset formats an 8-digit lowercase hex offset.
func Offset(n int) string {
	if n < 0 {
		n = 0
	}
	out := make([]byte, 8)
	for i := 7; i >= 0; i-- {
		out[i] = hexDigits[n&0xf]
		n >>= 4
	}
	return string(out)
}

// Hex formats one byte as two lowercase hex digits.
func Hex(b byte) string {
	return string([]byte{hexDigits[b>>4], hexDigits[b&0xf]})
}

// ASCII renders the printable-ASCII view of chunk: bytes outside 0x20..0x7e
// become ".". It is NOT padded — Line handles alignment.
func ASCII(chunk []byte) string {
	out := make([]byte, len(chunk))
	for i, c := range chunk {
		if c >= 0x20 && c <= 0x7e {
			out[i] = c
		} else {
			out[i] = '.'
		}
	}
	return string(out)
}

// Printable reports whether c renders as itself rather than as ".".
func Printable(c byte) bool { return c >= 0x20 && c <= 0x7e }
