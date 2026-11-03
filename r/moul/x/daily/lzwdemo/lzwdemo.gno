// Package lzwdemo is a small gnoweb demo of the Lempel-Ziv-Welch coder
// provided by the [p/moul/x/daily/lzw](/p/moul/x/daily/lzw/v0) library: the
// code stream for a worked example, the case that breaks a naive decoder, what
// repetition is worth, and where the code width grows.
//
// It contains no codec logic of its own. Everything on the page comes back
// from the library's own Steps, including the per-code widths, which is why
// there is nothing here that could drift away from the decoder. Stateless, so
// Render is deterministic: every figure is computed from the fixed strings at
// the top of this file, never from chain state, which is what lets an example
// test pin the page.
package lzwdemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/x/daily/lzw/v0"
)

// worked is the example small enough to check by hand: 11 bytes, four
// distinct, and two entries that are built and then reused.
const worked = "mississippi"

// repeated is the smallest input that reaches the decoder's hardest case. The
// encoder emits the code for "aa" on the very step that creates it.
const repeated = "aaaaa"

// samples show what repetition is worth. The first repeats nothing, the last
// is one short string over and over, and the ratio moves the whole way.
var samples = []string{
	"abcdefgh",
	"the quick brown fox jumps over the lazy dog",
	"mississippi",
	"abababababababababababababababab",
}

// Render renders the demo for gnoweb.
//
//	Render("") / Render("/") -> the worked stream, the hard case, the widths
//	Render("/<text>")        -> compress that text and show its stream
func Render(path string) string {
	if in := parseArg(path); in != "" {
		return renderInput(in)
	}

	var b strings.Builder
	b.WriteString("# LZW\n\n")
	b.WriteString("Dictionary compression, demoing the ")
	b.WriteString("[`p/moul/x/daily/lzw`](/p/moul/x/daily/lzw/v0) library. Both sides ")
	b.WriteString("start from the same 256 entries, one per byte, and both add the ")
	b.WriteString("same entry after every code, so the dictionary is never sent: the ")
	b.WriteString("payload is nothing but a stream of codes.\n\n")

	enc, err := lzw.Encode(worked)
	if err != nil {
		return b.String() + "> encoding failed: " + err.Error() + "\n"
	}
	steps, err := enc.Steps()
	if err != nil {
		return b.String() + "> decoding failed: " + err.Error() + "\n"
	}

	b.WriteString("## `" + worked + "`\n\n")
	t := ui.NewTable("#", "code", "means", "decoder adds")
	for i, s := range steps {
		t.Row(
			strconv.Itoa(i+1),
			strconv.Itoa(s.Code),
			md.InlineCode(s.Entry),
			newEntry(steps, i),
		)
	}
	b.WriteString(t.String() + "\n")
	b.WriteString("A code under 256 is a byte. Anything above it names a string ")
	b.WriteString("an earlier step added. The last column is the DECODER's table, ")
	b.WriteString("which runs one entry behind the encoder's: the encoder added ")
	b.WriteString("`mi` while emitting step 1, the decoder cannot add it until it ")
	b.WriteString("has read step 2, and step 9 adds nothing because the stream ends. ")
	b.WriteString(ratioLine(enc) + "\n\n")

	decoded, err := enc.Decode()
	b.WriteString("`Decode()` returns ")
	if err == nil && decoded == worked {
		b.WriteString("`" + decoded + "`, the input it started from. ✅\n\n")
	} else {
		b.WriteString("the wrong string. ❌\n\n")
	}

	b.WriteString("## The decoder is one entry behind\n\n")
	b.WriteString("The encoder can emit a code on the same step that creates it, ")
	b.WriteString("and the decoder then meets a code its table does not hold. ")
	b.WriteString("It happens on any run of a repeating pattern, and `" + repeated + "` ")
	b.WriteString("is the shortest input that does it:\n\n")
	if rep, err := lzw.Encode(repeated); err == nil {
		if rs, err := rep.Steps(); err == nil {
			rt := ui.NewTable("#", "code", "means", "in the table yet?")
			for i, s := range rs {
				// The decoder's table holds 256+(i-1) entries when it
				// reads step i, so a code equal to 255+i is exactly one
				// past the end of it and cannot be looked up.
				known := "yes"
				if i > 0 && s.Code == 255+i {
					known = "**no, synthesised**"
				}
				rt.Row(
					strconv.Itoa(i+1),
					strconv.Itoa(s.Code),
					md.InlineCode(s.Entry),
					known,
				)
			}
			b.WriteString(rt.String() + "\n")
		}
	}
	b.WriteString("The entry cannot be anything but the previous one with its own ")
	b.WriteString("first byte appended, because that is the only string the encoder ")
	b.WriteString("could have built there. A decoder that only looks codes up ")
	b.WriteString("returns an error on five bytes of `a`.\n\n")

	b.WriteString("## What repetition is worth\n\n")
	st := ui.NewTable("input", "codes", "raw", "coded", "saved")
	for _, s := range samples {
		e, err := lzw.Encode(s)
		if err != nil {
			continue
		}
		codes, err := e.Codes()
		if err != nil {
			continue
		}
		st.Row(
			md.InlineCode(s),
			strconv.Itoa(len(codes)),
			strconv.Itoa(e.Size*8)+" bits",
			strconv.Itoa(e.NBits)+" bits",
			strconv.Itoa(percent(e))+"%",
		)
	}
	b.WriteString(st.String() + "\n")
	b.WriteString("Short and unrepeating loses: nine-bit codes standing in for ")
	b.WriteString("eight-bit bytes cost an eighth more, and LZW has nothing to sell ")
	b.WriteString("until a string comes back a second time. That is the opposite ")
	b.WriteString("trade from Huffman, which pays for a table up front and then wins ")
	b.WriteString("on skew rather than on repetition.\n\n")

	b.WriteString("## The code width grows with the dictionary\n\n")
	b.WriteString("Codes start at nine bits and widen as the table fills. The ")
	b.WriteString("encoder widens after adding the entry that filled the old width; ")
	b.WriteString("the decoder has added one fewer by then, so it has to widen one ")
	b.WriteString("entry early or every later code comes out shifted by a bit. That ")
	b.WriteString("does not fail, it returns a different string, which is why it is ")
	b.WriteString("the bug LZW is known for.\n\n")
	wide, err := lzw.Encode(lowRedundancy())
	if err != nil {
		b.WriteString("> encoding failed: " + err.Error() + "\n")
		return b.String()
	}
	ws, err := wide.Steps()
	if err != nil {
		b.WriteString("> decoding failed: " + err.Error() + "\n")
		return b.String()
	}
	wt := ui.NewTable("width", "first code at it", "dictionary size there")
	prev := 0
	for i, s := range ws {
		if s.Width == prev {
			continue
		}
		prev = s.Width
		wt.Row(
			strconv.Itoa(s.Width)+" bits",
			"#"+strconv.Itoa(i+1),
			strconv.Itoa(256+i),
		)
	}
	b.WriteString(wt.String() + "\n")
	b.WriteString("Measured on " + strconv.Itoa(wide.Size) + " bytes that repeat ")
	b.WriteString("little: " + strconv.Itoa(len(ws)) + " codes, ")
	b.WriteString(strconv.Itoa(wide.NBits) + " bits. The next two steps are at ")
	b.WriteString("code 769 and code 1793, and then the table freezes at ")
	b.WriteString(strconv.Itoa(lzw.MaxWidth) + " bits: this coder has no reset ")
	b.WriteString("code, so a stream has exactly one reading.\n\n")

	b.WriteString("## Try your own\n\n")
	b.WriteString("```\n/r/moul/x/daily/lzwdemo/v0:mississippi\n```\n")
	return b.String()
}

// renderInput compresses a caller's text. Everything echoed back goes through
// md.InlineCode or ui.Cell: the string arrives from the URL and is
// attacker-controlled markdown until it is escaped. A hand-built code span
// would not do, because an escaped backtick still closes the span.
func renderInput(in string) string {
	var b strings.Builder
	b.WriteString("# LZW\n\n")
	b.WriteString("Input: " + md.InlineCode(in) + "\n\n")

	enc, err := lzw.Encode(in)
	if err != nil {
		b.WriteString("> " + ui.Inline(err.Error()) + "\n")
		return b.String()
	}
	steps, err := enc.Steps()
	if err != nil {
		b.WriteString("> " + ui.Inline(err.Error()) + "\n")
		return b.String()
	}

	t := ui.NewTable("#", "code", "bits", "means")
	for i, s := range steps {
		t.Row(
			strconv.Itoa(i+1),
			strconv.Itoa(s.Code),
			strconv.Itoa(s.Width),
			md.InlineCode(s.Entry),
		)
	}
	b.WriteString(t.String() + "\n")
	b.WriteString(ratioLine(enc) + "\n\n")
	b.WriteString("[back](/r/moul/x/daily/lzwdemo/v0)\n")
	return b.String()
}

// newEntry names the dictionary entry step i creates, which is the previous
// step's string plus the first byte of this one. The last step creates
// nothing: there is no following byte to extend it with.
func newEntry(steps []lzw.Step, i int) string {
	if i == 0 || i == len(steps)-1 {
		return ""
	}
	return strconv.Itoa(255+i) + " = " + md.InlineCode(steps[i-1].Entry+steps[i].Entry[0:1])
}

// ratioLine states the budget in one sentence.
func ratioLine(e *lzw.Encoded) string {
	return strconv.Itoa(e.NBits) + " bits against " + strconv.Itoa(e.Size*8) +
		" raw, " + strconv.Itoa(e.Saved()) + " saved (" + strconv.Itoa(percent(e)) + "%)."
}

// percent is the saving as a whole number. Integer arithmetic: a Render that
// prints a float is a Render that prints a different float on another node.
func percent(e *lzw.Encoded) int {
	raw := e.Size * 8
	if raw == 0 {
		return 0
	}
	return e.Saved() * 100 / raw
}

// lowRedundancy builds an input the dictionary cannot get ahead of: every byte
// value in turn, three times over. The first pass teaches it 256 pairs and
// nothing else, which is exactly what it takes to reach the first width
// change, and the two later passes cash some of them in.
//
// It is built rather than stored because a 768-byte literal in a realm is 768
// bytes of package source on chain, paid for once at deploy and read on every
// call.
func lowRedundancy() string {
	b := make([]byte, 0, 768)
	for pass := 0; pass < 3; pass++ {
		for i := 0; i < 256; i++ {
			b = append(b, byte(i))
		}
	}
	return string(b)
}

func parseArg(path string) string {
	s := strings.TrimSpace(path)
	s = strings.TrimPrefix(s, "/")
	return s
}
