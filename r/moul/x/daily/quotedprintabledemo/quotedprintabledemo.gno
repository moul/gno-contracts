// Package quotedprintabledemo is a small gnoweb demo of the quoted-printable
// codec provided by the
// [p/moul/x/daily/quotedprintable](/p/moul/x/daily/quotedprintable/v0) library:
// it puts the body ruleset (RFC 2045) and the header-word ruleset (RFC 2047)
// side by side, which is the whole reason the library exposes both.
//
// It contains no codec logic of its own. Stateless, so Render is deterministic.
package quotedprintabledemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/x/daily/quotedprintable/v0"
)

// Fixed inputs, so the rendered page never moves with chain state.
var vectors = []string{
	"hello world",
	"café",
	"a=b",
	"why not?",
	"trailing space ",
	"two\r\nlines",
}

// Render renders the demo for gnoweb.
//
//	Render("")        / Render("/") -> the two rulesets, then soft breaks
//	Render("/<text>")               -> encode that text both ways
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# Quoted-Printable\n\n")
	b.WriteString("RFC 2045 bodies and RFC 2047 header words, demoing the ")
	b.WriteString("[`p/moul/x/daily/quotedprintable`](/p/moul/x/daily/quotedprintable/v0) library.\n\n")

	if in := parseArg(path); in != "" {
		b.WriteString("## " + md.InlineCode(visible(in)) + "\n\n")
		body, err := quotedprintable.Encode(in)
		if err != nil {
			b.WriteString("- body: " + err.Error() + "\n")
		} else {
			b.WriteString("- body: " + md.InlineCode(visible(body)) + "\n")
		}
		word, err := quotedprintable.EncodeWord(in)
		if err != nil {
			b.WriteString("- header word: " + err.Error() + "\n")
		} else {
			b.WriteString("- header word: " + md.InlineCode(visible(word)) + "\n")
		}
		return b.String()
	}

	b.WriteString("## The same bytes, two rulesets\n\n")
	t := ui.NewTable("input", "body (RFC 2045)", "header word (RFC 2047)")
	for _, v := range vectors {
		body, _ := quotedprintable.Encode(v)
		word, _ := quotedprintable.EncodeWord(v)
		t.Row(md.InlineCode(visible(v)), md.InlineCode(visible(body)), md.InlineCode(visible(word)))
	}
	b.WriteString(t.String())

	b.WriteString("\n> A body leaves a space and a `?` alone; a header word cannot, ")
	b.WriteString("because a header is parsed into tokens before anything looks at the text. ")
	b.WriteString("That is why the space becomes `_` and the `?` becomes `=3F`. ")
	b.WriteString("Encoding a subject line with the body codec is the classic bug: it looks ")
	b.WriteString("encoded, and the receiving parser stops at the first `?`.\n")

	b.WriteString("\n## Soft breaks at 76 columns\n\n")
	long, _ := quotedprintable.Encode(strings.Repeat("gno", 100))
	b.WriteString("300 literal characters, wrapped by the encoder:\n\n")
	for _, l := range strings.Split(long, "\r\n") {
		b.WriteString("- `" + l + "` (" + strconv.Itoa(len(l)) + ")\n")
	}
	b.WriteString("\n> The trailing `=` is the soft break: it says the line was wrapped by the ")
	b.WriteString("encoder and is not a line of the data. 76 columns is the RFC's hard limit ")
	b.WriteString("and the `=` counts toward it, so the content stops at 75.\n")

	b.WriteString("\n## Every byte survives\n\n")
	raw := "a\r\nb"
	enc, _ := quotedprintable.Encode(raw)
	dec, err := quotedprintable.Decode(enc)
	b.WriteString("`" + visible(raw) + "` encodes to `" + visible(enc) + "`")
	if err == nil && dec == raw {
		b.WriteString(" and decodes back unchanged ✅\n")
	} else {
		b.WriteString(" and does not survive the round trip ❌\n")
	}
	b.WriteString("\n> CR and LF are encoded as data rather than written out as line structure. ")
	b.WriteString("A realm encodes a payload, not a mail message, and an encoder that ")
	b.WriteString("normalised line endings on the way through would quietly break a signature.\n")
	return b.String()
}

// visible makes the invisible bytes of an encoded string readable in markdown,
// so a soft break shows up as the two characters it is.
func visible(s string) string {
	s = strings.ReplaceAll(s, "\r", "\\r")
	s = strings.ReplaceAll(s, "\n", "\\n")
	return strings.ReplaceAll(s, "\t", "\\t")
}

func parseArg(path string) string {
	s := strings.TrimSpace(path)
	s = strings.TrimPrefix(s, "/")
	if i := strings.IndexByte(s, '/'); i >= 0 {
		s = s[:i]
	}
	return s
}
