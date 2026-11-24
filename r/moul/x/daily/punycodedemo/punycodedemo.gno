// Package punycodedemo is a small gnoweb demo of the RFC 3492 codec provided by
// the [p/moul/x/daily/punycode](/p/moul/x/daily/punycode/v0) library: it shows
// the label vectors, the `xn--` domain form, and the one property that makes
// punycode different from an ordinary codec.
//
// It contains no codec logic of its own. Stateless, so Render is deterministic.
package punycodedemo

import (
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/x/daily/punycode/v0"
)

// Fixed inputs, never chain state: output that moved with the block height
// could not be pinned by an example test. Four of these are RFC 3492 section
// 7.1 vectors.
var labels = []string{
	"abc",
	"bücher",
	"münchen",
	"αβγ",
	"мир",
	"日本語",
	"3年B組金八先生",
	"-> $1.00 <-",
}

var domains = []string{
	"example.com",
	"bücher.example",
	"münchen.de",
	"日本語.jp",
}

// Render renders the demo for gnoweb.
//
//	Render("")        / Render("/") -> the vectors, the domain form, the round trip
//	Render("/<text>")               -> encode that text as a label and as a domain
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# Punycode\n\n")
	b.WriteString("RFC 3492 bootstring, demoing the ")
	b.WriteString("[`p/moul/x/daily/punycode`](/p/moul/x/daily/punycode/v0) library.\n\n")

	// The argument is a caller's string and every echo of it is escaped: this
	// page is permanent, so a payload that closed a code span would stay closed.
	if in := parseArg(path); in != "" {
		lbl, err := punycode.Encode(in)
		dom, err2 := punycode.EncodeDomain(in)
		b.WriteString("## " + ui.Inline(in))
		b.WriteString("\n\n")
		b.WriteString("- label: " + echo(lbl, err) + "\n")
		b.WriteString("- domain: " + echo(dom, err2) + "\n")
		return b.String()
	}

	t := ui.NewTable("input", "punycode")
	for _, l := range labels {
		enc, err := punycode.Encode(l)
		t.Row(md.InlineCode(l), fixed(enc, err))
	}
	b.WriteString(t.OrEmpty("No vectors."))

	b.WriteString("\n## As a domain name\n\n")
	b.WriteString("Per label, and only where a label needed it: that is the `xn--` prefix.\n\n")
	d := ui.NewTable("unicode", "wire form")
	for _, name := range domains {
		enc, err := punycode.EncodeDomain(name)
		d.Row(md.InlineCode(name), fixed(enc, err))
	}
	b.WriteString(d.OrEmpty("No domains."))

	b.WriteString("\n## The ASCII stays readable\n\n")
	b.WriteString("Punycode is not a cipher over bytes. Every basic character is written out ")
	b.WriteString("first, verbatim, and only the positions of the rest are compressed ")
	b.WriteString("afterwards, so a mostly-ASCII label stays mostly legible:\n\n")
	sample := "Hello-münchen-2024"
	enc, err := punycode.Encode(sample)
	b.WriteString("- " + md.InlineCode(sample) + " encodes to " + fixed(enc, err) + "\n")
	if err == nil {
		back, err2 := punycode.Decode(enc)
		b.WriteString("- and decodes back to " + fixed(back, err2) + "\n")
	}

	b.WriteString("\n> No nameprep, no normalization, no confusable check. ")
	b.WriteString("This encodes what it is given, so it is a codec and not an answer ")
	b.WriteString("to whether two domain names are the same.\n")
	return b.String()
}

// fixed renders one of this file's own constants, or the error that replaced
// it, so a failure shows up on the page instead of as an empty cell.
func fixed(s string, err error) string {
	if err != nil {
		return "❌ " + err.Error()
	}
	return md.InlineCode(s)
}

// echo renders a value derived from the caller's argument. It goes through
// ui.Inline, not a code span: EncodeDomain passes an ASCII label straight
// through, so the caller's bytes can reach the page unchanged.
func echo(s string, err error) string {
	if err != nil {
		return "❌ " + err.Error()
	}
	return ui.Inline(s)
}

func parseArg(path string) string {
	s := strings.TrimSpace(path)
	s = strings.TrimPrefix(s, "/")
	if i := strings.IndexByte(s, '/'); i >= 0 {
		s = s[:i]
	}
	return s
}
