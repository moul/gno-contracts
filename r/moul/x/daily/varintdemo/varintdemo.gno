// Package varintdemo is a small gnoweb demo of the
// [p/moul/x/daily/varint](/p/moul/x/daily/varint/v0) library: it shows what the
// group boundaries cost, what zigzag buys on negative numbers, and which
// encodings the decoder refuses.
//
// It contains no codec logic of its own. Stateless, so Render is deterministic.
package varintdemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/x/daily/varint/v0"
)

// Fixed inputs, never chain state: a demo whose output moves with the block
// height cannot be pinned by an example test.
var (
	unsigned = []uint64{0, 1, 127, 128, 300, 16383, 16384, 1 << 32, 1<<64 - 1}
	signed   = []int64{0, -1, 1, -64, 64, -1 << 63, 1<<63 - 1}
	rejected = []struct{ label, in string }{
		{"`80 00`, zero with one padding group", "\x80\x00"},
		{"`81 00`, one with one padding group", "\x81\x00"},
		{"`80`, continuation bit then nothing", "\x80"},
		{"`ff ... ff 02`, ten groups, eleven bits too many", "\xff\xff\xff\xff\xff\xff\xff\xff\xff\x02"},
	}
)

// Render renders the demo for gnoweb.
//
//	Render("") / Render("/")  -> the vector tables and the refusals
//	Render("/<integer>")      -> encode that integer both ways
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# Varint\n\n")
	b.WriteString("LEB128 base-128 integers, demoing the ")
	b.WriteString("[`p/moul/x/daily/varint`](/p/moul/x/daily/varint/v0) library.\n\n")

	if arg := parseArg(path); arg != "" {
		b.WriteString(renderOne(arg))
		return b.String()
	}

	b.WriteString("## Unsigned\n\n")
	b.WriteString("Seven payload bits per byte, so the length steps at every power of 128.\n\n")
	t := ui.NewTable("value", "encoding", "bytes")
	for _, x := range unsigned {
		t.Row("`"+strconv.FormatUint(x, 10)+"`", "`"+hex(varint.PutUvarint(x))+"`", strconv.Itoa(varint.Len(x)))
	}
	b.WriteString(t.String())

	b.WriteString("\n## Signed, through zigzag\n\n")
	b.WriteString("Encoding a negative directly would sign-extend it to ten bytes. ")
	b.WriteString("Zigzag interleaves the signs first, so `-1` costs one byte and not ten.\n\n")
	t = ui.NewTable("value", "zigzag", "encoding", "bytes")
	for _, x := range signed {
		t.Row(
			"`"+strconv.FormatInt(x, 10)+"`",
			"`"+strconv.FormatUint(varint.ZigZag(x), 10)+"`",
			"`"+hex(varint.PutVarint(x))+"`",
			strconv.Itoa(varint.LenVarint(x)),
		)
	}
	b.WriteString(t.String())

	b.WriteString("\n## Only the canonical encoding decodes\n\n")
	b.WriteString("A padded varint means the same number has two spellings, which is a ")
	b.WriteString("different hash for the same state. The decoder refuses them.\n\n")
	t = ui.NewTable("input", "result")
	for _, c := range rejected {
		_, _, err := varint.Uvarint(c.in)
		t.Row(c.label, "`"+err.Error()+"`")
	}
	b.WriteString(t.String())

	b.WriteString("\n> Try another value: append it to the path, for instance ")
	b.WriteString("[`/-300`](/r/moul/x/daily/varintdemo/v0:/-300).\n")
	return b.String()
}

// renderOne encodes a single integer supplied in the path.
//
// The argument is the visitor's text and it is shown inside a code span, so
// it goes through md.InlineCode and not ui.Cell: a cell escaper backslashes
// a backtick, and a backslash does not close a backtick inside a span. Only
// a fence wider than anything in the argument does, which is what
// md.InlineCode picks.
func renderOne(arg string) string {
	var b strings.Builder
	b.WriteString("## ")
	b.WriteString(md.InlineCode(arg))
	b.WriteString("\n\n")

	unsigned := false
	if u, err := strconv.ParseUint(arg, 10, 64); err == nil {
		unsigned = true
		b.WriteString("- unsigned: `" + hex(varint.PutUvarint(u)) + "` (" + strconv.Itoa(varint.Len(u)) + " bytes)\n")
	}
	i, err := strconv.ParseInt(arg, 10, 64)
	if err != nil {
		// Above MaxInt64 the unsigned line above is the whole answer: the
		// codec carries the value, only the signed form cannot hold it.
		if !unsigned {
			b.WriteString("Not an integer this codec can carry: 64 bits, signed or unsigned.\n")
		}
		return b.String()
	}
	b.WriteString("- zigzag: `" + strconv.FormatUint(varint.ZigZag(i), 10) + "`\n")
	b.WriteString("- signed: `" + hex(varint.PutVarint(i)) + "` (" + strconv.Itoa(varint.LenVarint(i)) + " bytes)\n")
	return b.String()
}

// hex renders a byte string as lowercase hex pairs. Presentation only: the
// library deals in bytes and says nothing about how they are shown.
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

// parseArg takes the one routing slash off and nothing else. It does not cut
// at a later slash and it does not trim: a page that offers to encode what
// the caller typed either encodes that string or says it refused it, and
// never quietly substitutes a shorter or tidier one.
func parseArg(path string) string {
	return strings.TrimPrefix(path, "/")
}
