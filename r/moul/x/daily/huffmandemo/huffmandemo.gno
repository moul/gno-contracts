// Package huffmandemo is a small gnoweb demo of the canonical Huffman codec
// provided by the [p/moul/x/daily/huffman](/p/moul/x/daily/huffman/v0)
// library: the code table for a worked example, what the packed stream looks
// like, what the skew is worth, and the two inputs that break a naive
// implementation.
//
// It contains no codec logic of its own. Stateless, so Render is
// deterministic: every figure below is computed from the fixed strings at the
// top of this file, never from chain state, which is what lets an example test
// pin the page.
package huffmandemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/x/daily/huffman/v0"
)

// worked is the example small enough to check by hand: 11 bytes, 5 symbols,
// frequencies 5/2/2/1/1.
const worked = "abracadabra"

// samples show what the skew is worth. The first is flat by construction, the
// last is almost all one symbol, and the ratio moves the whole way between.
var samples = []string{
	"abcdefgh",
	"the quick brown fox jumps over the lazy dog",
	"mississippi",
	"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaabcd",
}

// Render renders the demo for gnoweb.
//
//	Render("") / Render("/") -> the worked example, the ratios, the edge cases
//	Render("/<text>")        -> encode that text and show its table
func Render(path string) string {
	if in := parseArg(path); in != "" {
		return renderInput(in)
	}

	var b strings.Builder
	b.WriteString("# Huffman coding\n\n")
	b.WriteString("Frequency-based prefix codes, demoing the ")
	b.WriteString("[`p/moul/x/daily/huffman`](/p/moul/x/daily/huffman/v0) library. ")
	b.WriteString("Rare symbols get long codes, common ones get short codes, and no ")
	b.WriteString("code is a prefix of another, so the stream needs no separators.\n\n")

	enc, err := huffman.Encode(worked)
	if err != nil {
		return b.String() + "> encoding failed: " + err.Error() + "\n"
	}

	b.WriteString("## `" + worked + "`\n\n")
	t := ui.NewTable("symbol", "count", "code", "bits")
	for _, c := range enc.Codes {
		t.Row(
			symbolLabel(c.Symbol),
			strconv.Itoa(countByte(worked, c.Symbol)),
			"`"+c.String()+"`",
			strconv.Itoa(c.Len),
		)
	}
	b.WriteString(t.String() + "\n")
	b.WriteString("The table is sorted by (length, symbol) and the codes are assigned ")
	b.WriteString("from the lengths alone. That is what canonical means: the decoder ")
	b.WriteString("rebuilds every code from one small integer per symbol, and two runs ")
	b.WriteString("over the same input can never disagree about the table.\n\n")

	b.WriteString("### The stream\n\n")
	b.WriteString("```\n" + enc.BitString() + "\n```\n\n")
	b.WriteString(ratioLine(enc) + "\n\n")

	decoded, err := enc.Decode()
	b.WriteString("`Decode()` returns ")
	if err == nil && decoded == worked {
		b.WriteString("`" + decoded + "`, the input it started from. ✅\n\n")
	} else {
		b.WriteString("the wrong string. ❌\n\n")
	}

	b.WriteString("## What the skew is worth\n\n")
	st := ui.NewTable("input", "symbols", "raw", "coded", "saved")
	for _, s := range samples {
		e, err := huffman.Encode(s)
		if err != nil {
			continue
		}
		st.Row(
			md.InlineCode(s),
			strconv.Itoa(len(e.Codes)),
			strconv.Itoa(e.Size*8)+" bits",
			strconv.Itoa(e.NBits)+" bits",
			strconv.Itoa(percent(e))+"%",
		)
	}
	b.WriteString(st.String() + "\n")
	b.WriteString("The floor is the alphabet, not the algorithm: eight distinct ")
	b.WriteString("bytes used once each cost three bits apiece, which is what a ")
	b.WriteString("fixed-width code over eight symbols would have spent anyway. ")
	b.WriteString("Everything past that floor is bought with skew.\n\n")

	b.WriteString("## The two inputs that break a naive implementation\n\n")
	b.WriteString("**One distinct symbol.** Its leaf has no sibling, so the tree walk ")
	b.WriteString("gives it a zero-bit code and the stream comes out empty: ")
	if e, err := huffman.Encode("aaaaa"); err == nil && len(e.Codes) == 1 {
		b.WriteString("here `aaaaa` is `" + e.BitString() + "`, five one-bit codes, ")
		b.WriteString("and it is the only incomplete code the library emits.\n\n")
	} else {
		b.WriteString("the library refuses it instead.\n\n")
	}
	b.WriteString("**A payload that was edited.** `Decode` rebuilds the canonical ")
	b.WriteString("table from the lengths it was handed and refuses a payload whose ")
	b.WriteString("own bits disagree with it, so a stored `Encoded` cannot be bent ")
	b.WriteString("into decoding as a different string:\n\n")
	bent := &huffman.Encoded{
		Codes: append([]huffman.Code(nil), enc.Codes...),
		Data:  append([]byte(nil), enc.Data...),
		NBits: enc.NBits,
		Size:  enc.Size,
	}
	bent.Codes[1].Bits = 7
	if _, err := bent.Decode(); err != nil {
		b.WriteString("```\n" + err.Error() + "\n```\n\n")
	}

	b.WriteString("## Try your own\n\n")
	b.WriteString("```\n/r/moul/x/daily/huffmandemo/v0:mississippi\n```\n")
	return b.String()
}

// renderInput encodes a caller's text. Everything echoed back goes through
// md.InlineCode or ui.Inline: the string arrives from the URL and is
// attacker controlled markdown until it is escaped. A hand-built code span
// would not do, because an escaped backtick still closes the span.
func renderInput(in string) string {
	var b strings.Builder
	b.WriteString("# Huffman coding\n\n")
	b.WriteString("Input: " + md.InlineCode(in) + "\n\n")

	enc, err := huffman.Encode(in)
	if err != nil {
		b.WriteString("> " + ui.Inline(err.Error()) + "\n")
		return b.String()
	}

	t := ui.NewTable("symbol", "count", "code", "bits")
	for _, c := range enc.Codes {
		t.Row(
			symbolLabel(c.Symbol),
			strconv.Itoa(countByte(in, c.Symbol)),
			"`"+c.String()+"`",
			strconv.Itoa(c.Len),
		)
	}
	b.WriteString(t.String() + "\n")
	b.WriteString(ratioLine(enc) + "\n\n")
	b.WriteString("[back](/r/moul/x/daily/huffmandemo/v0)\n")
	return b.String()
}

// ratioLine states the budget in one sentence.
func ratioLine(e *huffman.Encoded) string {
	return strconv.Itoa(e.NBits) + " bits against " + strconv.Itoa(e.Size*8) +
		" raw, " + strconv.Itoa(e.Saved()) + " saved (" + strconv.Itoa(percent(e)) + "%)."
}

// percent is the saving as a whole number. Integer arithmetic: a Render that
// prints a float is a Render that prints a different float on another node.
func percent(e *huffman.Encoded) int {
	raw := e.Size * 8
	if raw == 0 {
		return 0
	}
	return e.Saved() * 100 / raw
}

// symbolLabel renders one byte for a table cell. A symbol is a BYTE, not a
// rune: converting a byte above 127 with string(b) produces a two-byte UTF-8
// sequence that is not the byte the code stands for, which would make the
// count beside it wrong for any non-ASCII input. Anything outside printable
// ASCII is shown as hex instead.
func symbolLabel(b byte) string {
	switch b {
	case ' ':
		return "`(space)`"
	case '`':
		return "`` ` ``"
	case '|':
		return "`(pipe)`"
	}
	if b < 0x20 || b > 0x7e {
		const hex = "0123456789abcdef"
		return "`0x" + string(hex[b>>4]) + string(hex[b&0x0f]) + "`"
	}
	return "`" + string(b) + "`"
}

// countByte counts one byte in s, for the same reason symbolLabel exists.
func countByte(s string, b byte) int {
	n := 0
	for i := 0; i < len(s); i++ {
		if s[i] == b {
			n++
		}
	}
	return n
}

func parseArg(path string) string {
	s := strings.TrimSpace(path)
	s = strings.TrimPrefix(s, "/")
	return s
}
