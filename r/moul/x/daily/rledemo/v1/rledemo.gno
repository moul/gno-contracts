// Package rledemo is a small gnoweb demo of the run-length codec provided by
// the [p/moul/x/daily/rle](/p/moul/x/daily/rle/v1) library: it encodes a few
// sample strings, round-trips them, and reports the size ratio — including the
// case where the "compression" makes things bigger.
//
// It contains no codec logic of its own. Stateless, so Render is deterministic.
package rledemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/x/daily/rle/v1"
)

// samples are picked to show both outcomes: runny data compresses, data
// without runs expands.
var samples = []string{
	"aaaaaaaaaabbbbbbbbbb",
	"aaabbc",
	"abcdef",
}

// Render renders the demo for gnoweb.
//
//	Render("")        / Render("/") -> the samples table
//	Render("/<text>")               -> encode that text
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# Run-Length Encoding\n\n")
	b.WriteString("`<count><char>` pairs, demoing the ")
	b.WriteString("[`p/moul/x/daily/rle`](/p/moul/x/daily/rle/v1) library.\n\n")

	if in := parseArg(path); in != "" {
		return b.String() + one(in)
	}

	b.WriteString("| input | encoded | size | round-trips |\n|---|---|---|---|\n")
	for _, s := range samples {
		enc, err := rle.Encode(s)
		if err != nil {
			continue
		}
		dec, _ := rle.Decode(enc)
		b.WriteString("| `")
		b.WriteString(s)
		b.WriteString("` | `")
		b.WriteString(enc)
		b.WriteString("` | ")
		b.WriteString(strconv.Itoa(rle.Ratio(s, enc)))
		b.WriteString("% | ")
		if dec == s {
			b.WriteString("✅")
		} else {
			b.WriteString("❌")
		}
		b.WriteString(" |\n")
	}
	b.WriteString("\n> Over 100% means the encoding made the data **bigger**. ")
	b.WriteString("RLE only wins on runny input, and `abcdef` is the honest counter-example.\n\n")
	b.WriteString("> Append text to the path to encode it — digits are rejected, ")
	b.WriteString("since they would be ambiguous with a run count.\n")
	return b.String()
}

func one(in string) string {
	var b strings.Builder
	b.WriteString("## `")
	b.WriteString(in)
	b.WriteString("`\n\n")
	enc, err := rle.Encode(in)
	if err != nil {
		b.WriteString("_")
		b.WriteString(err.Error())
		b.WriteString("_\n")
		return b.String()
	}
	dec, _ := rle.Decode(enc)
	b.WriteString("- encoded: `")
	b.WriteString(enc)
	b.WriteString("`\n- size: **")
	b.WriteString(strconv.Itoa(rle.Ratio(in, enc)))
	b.WriteString("%**\n- round-trips: ")
	if dec == in {
		b.WriteString("✅\n")
	} else {
		b.WriteString("❌\n")
	}
	return b.String()
}

func parseArg(path string) string {
	s := strings.TrimSpace(path)
	s = strings.TrimPrefix(s, "/")
	if i := strings.IndexByte(s, '/'); i >= 0 {
		s = s[:i]
	}
	return s
}
