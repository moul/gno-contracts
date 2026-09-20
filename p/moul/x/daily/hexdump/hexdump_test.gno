package hexdump

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestOffset(t *testing.T) {
	cases := []struct {
		in   int
		want string
	}{
		{0, "00000000"},
		{1, "00000001"},
		{15, "0000000f"},
		{16, "00000010"},
		{255, "000000ff"},
		{4096, "00001000"},
		{-5, "00000000"}, // clamped
	}
	for _, c := range cases {
		uassert.Equal(t, c.want, Offset(c.in))
	}
}

func TestHex(t *testing.T) {
	uassert.Equal(t, "00", Hex(0))
	uassert.Equal(t, "0f", Hex(15))
	uassert.Equal(t, "10", Hex(16))
	uassert.Equal(t, "ff", Hex(255))
	uassert.Equal(t, "41", Hex('A'))
}

func TestPrintable(t *testing.T) {
	uassert.False(t, Printable(0x00), "NUL is not printable")
	uassert.False(t, Printable(0x1f), "0x1f is below the printable range")
	uassert.True(t, Printable(0x20), "space is printable")
	uassert.True(t, Printable('A'))
	uassert.True(t, Printable(0x7e), "~ is the last printable")
	uassert.False(t, Printable(0x7f), "DEL is not printable")
	uassert.False(t, Printable(0xff))
}

func TestASCII(t *testing.T) {
	uassert.Equal(t, "ABC", ASCII([]byte("ABC")))
	uassert.Equal(t, "...", ASCII([]byte{0x00, 0x01, 0x7f}))
	uassert.Equal(t, "a.b", ASCII([]byte{'a', 0x00, 'b'}))
	uassert.Equal(t, "", ASCII(nil))
}

// TestLineFullWidth pins the exact classic layout, including the extra space
// between the two 8-byte groups.
func TestLineFullWidth(t *testing.T) {
	uassert.Equal(t,
		"00000000  30 31 32 33 34 35 36 37  38 39 61 62 63 64 65 66  |0123456789abcdef|",
		Line(0, []byte("0123456789abcdef")))
}

// TestLineShortChunkStaysAligned is the reason the padding exists: a partial
// final line must not shift the ASCII gutter.
func TestLineShortChunkStaysAligned(t *testing.T) {
	full := Line(0, []byte("0123456789abcdef"))
	short := Line(16, []byte("hi"))

	uassert.Equal(t,
		"00000010  68 69                                             |hi|",
		short)
	uassert.Equal(t, strings.Index(full, "|"), strings.Index(short, "|"),
		"the ASCII gutter must start at the same column on a short line")
}

func TestLineEmptyChunk(t *testing.T) {
	// All padding, empty gutter — still aligned.
	l := Line(0, nil)
	uassert.True(t, strings.HasSuffix(l, "||"), "empty chunk renders an empty gutter")
	uassert.Equal(t, strings.Index(Line(0, []byte("x")), "|"), strings.Index(l, "|"))
}

func TestDumpMultiLine(t *testing.T) {
	out, n := DumpString("0123456789abcdefhi")
	uassert.Equal(t, 18, n)
	uassert.Equal(t,
		"00000000  30 31 32 33 34 35 36 37  38 39 61 62 63 64 65 66  |0123456789abcdef|\n"+
			"00000010  68 69                                             |hi|\n",
		out)
}

func TestDumpEmpty(t *testing.T) {
	out, n := Dump(nil)
	uassert.Equal(t, "", out)
	uassert.Equal(t, 0, n)
}

func TestDumpNonPrintable(t *testing.T) {
	out, n := Dump([]byte{0x00, 0x0a, 0x41})
	uassert.Equal(t, 3, n)
	uassert.Equal(t, "00000000  00 0a 41                                          |..A|\n", out)
}

// TestDumpTruncates pins the bound and the honest byte count.
func TestDumpTruncates(t *testing.T) {
	_, n := DumpString(strings.Repeat("x", MaxBytes+100))
	uassert.Equal(t, MaxBytes, n, "input beyond MaxBytes is truncated")

	_, n = DumpString(strings.Repeat("x", MaxBytes))
	uassert.Equal(t, MaxBytes, n, "exactly MaxBytes is not truncated")
}

func TestDumpLineCount(t *testing.T) {
	out, _ := DumpString(strings.Repeat("x", 33))
	uassert.Equal(t, 3, strings.Count(out, "\n"), "33 bytes is 3 lines (16+16+1)")
}

// TestDumpRevealsInvisibleDifferences is the practical point of the package.
func TestDumpRevealsInvisibleDifferences(t *testing.T) {
	a, _ := DumpString("hi")
	b, _ := DumpString("hi ")
	uassert.False(t, a == b, "a trailing space is invisible rendered, obvious in a dump")

	// "é" is two bytes, not one.
	out, n := DumpString("é")
	uassert.Equal(t, 2, n)
	uassert.True(t, strings.Contains(out, "c3 a9"), "UTF-8 shows its real bytes")
}
