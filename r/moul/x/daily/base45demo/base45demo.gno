// Package base45demo is a small gnoweb demo of the base45 codec provided by
// the [p/moul/x/daily/base45](/p/moul/x/daily/base45/v0) library: it shows the
// RFC 9285 test vectors, the least-significant-first ordering that every
// reimplementation gets wrong, and the two boundaries a strict decoder has to
// refuse.
//
// It contains no codec logic of its own. Stateless, so Render is deterministic.
package base45demo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/x/daily/base45/v0"
)

// The RFC 9285 §4.4 vectors, plus the empty string.
var vectors = []string{"", "AB", "ietf!", "base-45", "Hello!!"}

// The two group boundaries. "FGW" is 0xFFFF and "GGW" is 0x10000; "U5" is 255
// and "V5" is 256. One character apart, and the second of each pair is a
// string no encoder ever produced.
var boundaries = []string{"FGW", "GGW", "U5", "V5", "B", "bb8"}

// Render renders the demo for gnoweb.
//
//	Render("")        / Render("/") -> the vectors, the ordering, the refusals
//	Render("/<text>")               -> encode that text
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# Base45\n\n")
	b.WriteString("The QR-alphanumeric encoding of RFC 9285, demoing the ")
	b.WriteString("[`p/moul/x/daily/base45`](/p/moul/x/daily/base45/v0) library.\n\n")

	if in := strings.TrimPrefix(path, "/"); in != "" {
		enc, err := base45.Encode(in)
		b.WriteString("Encoding " + ui.Inline(in) + ":\n\n")
		if err != nil {
			b.WriteString("> " + ui.Inline(err.Error()) + "\n")
			return b.String()
		}
		t := ui.NewTable("field", "value")
		t.Row("input", strconv.Itoa(len(in))+" bytes")
		t.Row("base45", ui.Cell(enc))
		t.Row("characters", strconv.Itoa(len(enc)))
		b.WriteString(t.String())
		return b.String()
	}

	b.WriteString("## The RFC 9285 vectors\n\n")
	vt := ui.NewTable("input", "base45", "characters")
	for _, v := range vectors {
		enc, _ := base45.Encode(v)
		in := md.InlineCode(v)
		out := md.InlineCode(enc)
		if v == "" {
			in, out = "_(empty)_", "_(empty)_"
		}
		vt.Row(in, out, strconv.Itoa(len(enc)))
	}
	b.WriteString(vt.String() + "\n")

	b.WriteString("## Least significant character first\n\n")
	b.WriteString("Two bytes are one 16-bit number written in base 45, and the three ")
	b.WriteString("characters come out in the order a human would call backwards. ")
	b.WriteString("`AB` is `0x4142`, which is 16706:\n\n")
	ot := ui.NewTable("place", "digit", "character")
	n := 16706
	ot.Row("45^0 = 1", strconv.Itoa(n%45), md.InlineCode(string(base45.Alphabet[n%45])))
	ot.Row("45^1 = 45", strconv.Itoa(n/45%45), md.InlineCode(string(base45.Alphabet[n/45%45])))
	ot.Row("45^2 = 2025", strconv.Itoa(n/2025), md.InlineCode(string(base45.Alphabet[n/2025])))
	b.WriteString(ot.String() + "\n")
	ab, _ := base45.Encode("AB")
	b.WriteString("Read down the table and you get " + md.InlineCode(ab))
	b.WriteString(", not `8BB`. An implementation that emits them the other way ")
	b.WriteString("round still round-trips against itself, so only a published ")
	b.WriteString("vector catches it.\n\n")

	b.WriteString("## What the decoder refuses\n\n")
	rt := ui.NewTable("string", "verdict")
	for _, s := range boundaries {
		out, err := base45.DecodeBytes(s)
		if err != nil {
			rt.Row(md.InlineCode(s), "rejected: "+err.Error())
			continue
		}
		rt.Row(md.InlineCode(s), "accepted, 0x"+hexOf(out))
	}
	b.WriteString(rt.String() + "\n")
	b.WriteString("A group above `0xFFFF` is truncation waiting to happen, a length ")
	b.WriteString("of 3n+1 is a character nobody wrote, and the alphabet is uppercase, ")
	b.WriteString("so `bb8` is corrupt input rather than a case to fold.\n\n")

	b.WriteString("Pass a string of your own to encode it: ")
	b.WriteString("`Render(\"/<text>\")`.\n")
	return b.String()
}

// hexOf renders decoded bytes as lowercase hex digits.
func hexOf(out []byte) string {
	const digits = "0123456789abcdef"
	var b strings.Builder
	for _, c := range out {
		b.WriteByte(digits[c>>4])
		b.WriteByte(digits[c&0x0f])
	}
	return b.String()
}
