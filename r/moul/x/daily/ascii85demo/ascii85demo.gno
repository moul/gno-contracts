// Package ascii85demo is a small gnoweb demo of the ascii85 codec provided by
// the [p/moul/x/daily/ascii85](/p/moul/x/daily/ascii85/v0) library: it shows
// what the encoding costs against base64 and hex, the zero-group shortcut that
// makes it not a fixed ratio, and the overflowing groups the library refuses
// where Go's standard library wraps them.
//
// It contains no codec logic of its own. Stateless and read-only, so Render is
// fully deterministic.
package ascii85demo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/x/daily/ascii85/v0"
)

// samples are the classic btoa inputs plus every partial-group length, so the
// table shows what the final group does at each remainder.
var samples = []string{"", "s", "su", "sur", "sure", "sure.", "Man ", "gno.land"}

// overflowing are texts made only of alphabet characters that name a group of
// 2^32 or more. Go's encoding/ascii85 holds the group in a uint32 and lets it
// wrap, so each of these decodes there to bytes that are nowhere in the input.
var overflowing = []string{"s8W-\"", "uuuuu", "s8W-#"}

// Render renders the demo for gnoweb.
//
//	Render("")       / Render("/") -> the cost, the shortcut and the refusals
//	Render("/<text>")              -> encode that text, bare and framed
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# ascii85\n\n")
	b.WriteString("Four bytes into five printable characters, demoing the ")
	b.WriteString("[`p/moul/x/daily/ascii85`](/p/moul/x/daily/ascii85/v0) library.\n\n")

	if in := parseArg(path); in != "" {
		return b.String() + renderOne(in)
	}
	return b.String() + renderCost() + renderShortcut() + renderRefusals()
}

// renderOne encodes one caller-supplied string.
func renderOne(in string) string {
	var b strings.Builder
	b.WriteString("## ")
	b.WriteString(ui.Inline(in))
	b.WriteString("\n\n")

	enc, err := ascii85.Encode(in)
	if err != nil {
		b.WriteString("Refused: ")
		b.WriteString(ui.Inline(err.Error()))
		b.WriteString("\n")
		return b.String()
	}
	framed, _ := ascii85.EncodeFramed(in)
	back, err := ascii85.Decode(framed)

	t := ui.NewTable("form", "output")
	t.Row("bare", md.InlineCode(enc))
	t.Row("framed", md.InlineCode(framed))
	t.Row("bytes in", strconv.Itoa(len(in)))
	t.Row("characters out", strconv.Itoa(len(enc)))
	t.Row("round trip", roundTrip(in, back, err))
	b.WriteString(t.String())
	b.WriteString("\n> The framed form is what a PostScript or PDF stream carries. ")
	b.WriteString("`Decode` takes either, and ignores the line breaks an encoder inserts.\n")
	return b.String()
}

// roundTrip states whether decoding gave the input back.
func roundTrip(in, back string, err error) string {
	if err == nil && back == in {
		return "exact ✅"
	}
	return "lost ❌"
}

// renderCost shows the expansion against the two codecs it competes with.
func renderCost() string {
	var b strings.Builder
	b.WriteString("## What it costs\n\n")

	t := ui.NewTable("input", "bytes", "ascii85", "characters")
	for _, s := range samples {
		enc, err := ascii85.Encode(s)
		if err != nil {
			continue
		}
		label := md.InlineCode(s)
		shown := md.InlineCode(enc)
		if s == "" {
			label, shown = "_(empty)_", "_(empty)_"
		}
		t.Row(label, strconv.Itoa(len(s)), shown, strconv.Itoa(len(enc)))
	}
	b.WriteString(t.String())

	b.WriteString("\nFive characters per four bytes is 25% expansion, against 33% for ")
	b.WriteString("base64 and 100% for hex. Encoding 400 bytes gives ")
	wide, _ := ascii85.Encode(strings.Repeat("x", 400))
	b.WriteString(strconv.Itoa(len(wide)))
	b.WriteString(" characters where base64 would give 536 and hex 800. ")
	b.WriteString("You pay for it with an alphabet that is neither URL-safe nor ")
	b.WriteString("case-insensitive, which is why base64 kept the web and ascii85 ")
	b.WriteString("kept PostScript.\n\n")
	return b.String()
}

// renderShortcut shows the zero group, which breaks the fixed ratio.
func renderShortcut() string {
	var b strings.Builder
	b.WriteString("## The zero shortcut\n\n")

	zeros, _ := ascii85.Encode("\x00\x00\x00\x00")
	aligned, _ := ascii85.Encode("abcd\x00\x00\x00\x00efgh")
	straddling, _ := ascii85.Encode("abc\x00\x00\x00\x00def")

	b.WriteString("Four zero bytes are written as the single character `")
	b.WriteString(zeros)
	b.WriteString("`, so the output is not a fixed ratio of the input: a run of ")
	b.WriteString("zeroes costs a fifth of what the arithmetic says.\n\n")
	b.WriteString("It only fires on a group boundary, which is the part that surprises:\n\n")
	b.WriteString("- `abcd` + four zeroes + `efgh` becomes `" + aligned + "`\n")
	b.WriteString("- `abc` + the same four zeroes + `def` becomes `" + straddling + "`\n\n")
	b.WriteString("The same four bytes, one character in the first and five in the second, ")
	b.WriteString("because in the second they are split across two groups and neither is ")
	b.WriteString("all zero. Decoding rejects a `")
	b.WriteString(zeros)
	b.WriteString("` that appears once a group has been started, for the same reason.\n\n")
	return b.String()
}

// renderRefusals shows the overflowing groups, the one place this library
// deliberately disagrees with Go's.
func renderRefusals() string {
	var b strings.Builder
	b.WriteString("## What it refuses\n\n")
	b.WriteString("A five-character group is a base-85 numeral, and only values below ")
	b.WriteString("2^32 name four bytes. Nothing in the alphabet stops a stream from ")
	b.WriteString("spelling a larger one, and Go's `encoding/ascii85` holds the group in ")
	b.WriteString("a `uint32` and lets it wrap:\n\n")

	t := ui.NewTable("group", "names", "here")
	for _, s := range overflowing {
		_, err := ascii85.Decode(s)
		msg := "accepted"
		if err != nil {
			msg = "refused: " + md.InlineCode(err.Error())
		}
		t.Row(md.InlineCode(s), "2^32 or more", msg)
	}
	largest, err := ascii85.Decode("s8W-!")
	kept := "refused"
	if err == nil {
		kept = strconv.Itoa(len(largest)) + " bytes, all `0xFF`"
	}
	t.Row("`s8W-!`", "2^32 - 1", kept)
	b.WriteString(t.String())

	b.WriteString("\n> Two different texts decoding to the same bytes is a forgery ")
	b.WriteString("primitive wherever the text is what gets signed, compared or used as ")
	b.WriteString("a key. `s8W-\"` is 2^32 exactly, and in Go it decodes to the same four ")
	b.WriteString("zero bytes as the one-character shortcut.\n")
	return b.String()
}

// parseArg extracts the first path segment.
func parseArg(path string) string {
	s := strings.TrimSpace(path)
	s = strings.TrimPrefix(s, "/")
	if i := strings.IndexByte(s, '/'); i >= 0 {
		s = s[:i]
	}
	return s
}
