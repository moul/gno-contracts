// Package cobsdemo is a small gnoweb demo of the
// [p/moul/x/daily/cobs](/p/moul/x/daily/cobs/v0) library: it shows what a
// frame looks like, why a payload of zeros is the cheap case and not the
// expensive one, and what a stream of records costs once it is packed.
//
// It contains no codec logic of its own. Stateless, so Render is
// deterministic.
package cobsdemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/x/daily/cobs/v0"
)

// Fixed inputs, never chain state: a demo whose output moves with the block
// height cannot be pinned by an example test.
var (
	// The rows of Table 1 in Cheshire and Baker, abbreviated where the paper
	// prints a 254-byte run.
	vectors = []struct{ label, in string }{
		{"the empty payload", ""},
		{"one zero", "\x00"},
		{"two zeros", "\x00\x00"},
		{"a zero in the middle", "\x11\x22\x00\x33"},
		{"no zero at all", "\x11\x22\x33\x44"},
		{"three trailing zeros", "\x11\x00\x00\x00"},
	}

	// A record set a realm might actually store: arbitrary bytes, zeros
	// included, that still has to come apart again later.
	records = []string{"alice", "\x00\x00", "a\x00b", "", "bob"}

	// Lengths worth showing side by side, because the two extremes are the
	// opposite way round from what escaping teaches.
	lengths = []int{1, 254, 255, 509, 1000}

	rejected = []struct{ label, in string }{
		{"a zero inside the frame", "\x03\x11\x00"},
		{"a code byte promising 4 bytes, 2 given", "\x05\x11\x22"},
		{"nothing at all", ""},
		{"a full group padded with an empty one", "\xff" + run(0x01, 0xfe) + "\x01"},
	}
)

// Render renders the demo for gnoweb.
//
//	Render("") / Render("/")  -> the vectors, the overhead table, the refusals
//	Render("/<text>")         -> frame that text and show the bytes
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# COBS\n\n")
	b.WriteString("Consistent Overhead Byte Stuffing, demoing the ")
	b.WriteString("[`p/moul/x/daily/cobs`](/p/moul/x/daily/cobs/v0) library.\n\n")

	if arg := parseArg(path); arg != "" {
		b.WriteString(renderOne(arg))
		return b.String()
	}

	b.WriteString("## A frame, byte for byte\n\n")
	b.WriteString("Each group is a code byte then up to 254 non-zero bytes. ")
	b.WriteString("The code is the group length plus one, and a group under the maximum ")
	b.WriteString("ends in a zero the frame does not store.\n\n")
	t := ui.NewTable("payload", "frame", "bytes")
	for _, c := range vectors {
		t.Row(
			c.label+" `"+hex(c.in)+"`",
			"`"+hex(cobs.Encode(c.in))+"`",
			strconv.Itoa(len(c.in))+" to "+strconv.Itoa(len(cobs.Encode(c.in))),
		)
	}
	b.WriteString(t.String())

	b.WriteString("\n## The payload an escaper fears is the cheap one here\n\n")
	b.WriteString("Escaping every zero doubles an all-zero payload. ")
	b.WriteString("COBS stores the distances between zeros instead, so an all-zero payload ")
	b.WriteString("costs exactly one byte, at any length, and the expensive direction is ")
	b.WriteString("the one with no zeros in it at all.\n\n")
	t = ui.NewTable("payload bytes", "all zeros", "no zeros", "escaping, worst case")
	for _, n := range lengths {
		zeros := strings.Repeat("\x00", n)
		dense := strings.Repeat("\x41", n)
		t.Row(
			strconv.Itoa(n),
			"+"+strconv.Itoa(len(cobs.Encode(zeros))-n),
			"+"+strconv.Itoa(len(cobs.Encode(dense))-n),
			"+"+strconv.Itoa(n),
		)
	}
	b.WriteString(t.String())

	b.WriteString("\n## Packing records into one string\n\n")
	b.WriteString("The reason to remove the zeros: every boundary can then be found by ")
	b.WriteString("scanning for one, with no length table and no parsing.\n\n")
	packed := cobs.Pack(records)
	t = ui.NewTable("record", "frame")
	for _, r := range records {
		t.Row("`"+hex(r)+"`", "`"+hex(cobs.Frame(r))+"`")
	}
	b.WriteString(t.String())
	b.WriteString("\nPacked, the five records are " + strconv.Itoa(len(packed)))
	b.WriteString(" bytes carrying " + strconv.Itoa(payloadBytes(records)) + " of payload:\n\n")
	b.WriteString(md.CodeBlock(hex(packed)))
	back, err := cobs.Unpack(packed)
	if err != nil {
		b.WriteString("\nUnpack refused its own output: `" + err.Error() + "`\n")
		return b.String()
	}
	b.WriteString("\nand `Unpack` gives back " + strconv.Itoa(len(back)) + " records, ")
	b.WriteString("the empty one included.\n")

	b.WriteString("\n## What the decoder refuses\n\n")
	b.WriteString("A frame is checked, never repaired: a short payload looks exactly like ")
	b.WriteString("a complete one, and a payload with two frames is two hashes for one ")
	b.WriteString("piece of state.\n\n")
	t = ui.NewTable("frame", "result")
	for _, c := range rejected {
		_, err := cobs.Decode(c.in)
		if err == nil {
			// A row that stopped being refused is a demo lying about the
			// codec, and reading .Error() off a nil here would panic the
			// page instead of saying so.
			t.Row(c.label, "accepted, and this table says it should not be")
			continue
		}
		t.Row(c.label, "`"+err.Error()+"`")
	}
	b.WriteString(t.String())

	b.WriteString("\n> Frame your own text: append it to the path, for instance ")
	b.WriteString("[`/hello`](/r/moul/x/daily/cobsdemo/v0:/hello).\n")
	return b.String()
}

// renderOne frames a single string supplied in the path.
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

	frame := cobs.Encode(arg)
	b.WriteString("- payload: `" + hex(arg) + "` (" + strconv.Itoa(len(arg)) + " bytes)\n")
	b.WriteString("- frame: `" + hex(frame) + "` (" + strconv.Itoa(len(frame)) + " bytes)\n")
	b.WriteString("- overhead: " + strconv.Itoa(len(frame)-len(arg)) + " of at most ")
	b.WriteString(strconv.Itoa(cobs.MaxEncodedLen(len(arg))-len(arg)) + "\n")

	// Round-tripping on the page is the claim worth making in public: the
	// bytes above are not just shorter, they are the same bytes back.
	back, err := cobs.Decode(frame)
	if err != nil {
		b.WriteString("- decode: `" + err.Error() + "`\n")
		return b.String()
	}
	if back != arg {
		b.WriteString("- decode: returned a different payload\n")
		return b.String()
	}
	b.WriteString("- decode: the same " + strconv.Itoa(len(back)) + " bytes back\n")
	return b.String()
}

// payloadBytes totals the unencoded length of a record set, so the packed
// figure next to it is a comparison and not a bare number.
func payloadBytes(rs []string) int {
	n := 0
	for _, r := range rs {
		n += len(r)
	}
	return n
}

// run returns the bytes lo..hi inclusive, which is how the paper writes its
// long vectors.
func run(lo, hi byte) string {
	var b strings.Builder
	for c := int(lo); c <= int(hi); c++ {
		b.WriteByte(byte(c))
	}
	return b.String()
}

// hex renders a byte string as lowercase hex pairs, and an empty one as a
// placeholder rather than an empty cell. Presentation only: the library deals
// in bytes and says nothing about how they are shown.
func hex(s string) string {
	if s == "" {
		return "(none)"
	}
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
// at a later slash and it does not trim: a page that offers to frame what the
// caller typed either frames that string or says it refused it, and never
// quietly substitutes a shorter or tidier one.
func parseArg(path string) string {
	return strings.TrimPrefix(path, "/")
}
