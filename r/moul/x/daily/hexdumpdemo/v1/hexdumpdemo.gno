// Package hexdumpdemo is a small gnoweb demo of the xxd-style byte dump
// provided by the [p/moul/x/daily/hexdump](/p/moul/x/daily/hexdump/v1)
// library: it shows what a rendered string hides.
//
// It contains no formatting logic of its own. Stateless, so Render is
// deterministic — which is precisely what the library is for.
package hexdumpdemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/x/daily/hexdump/v1"
)

// Render renders the demo for gnoweb.
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# Hexdump\n\n")
	b.WriteString("Bytes in the classic `xxd -C` layout, demoing the ")
	b.WriteString("[`p/moul/x/daily/hexdump`](/p/moul/x/daily/hexdump/v1) library.\n\n")

	b.WriteString("## A plain string\n\n")
	dump("Hello, gno.land!", &b)

	b.WriteString("\n## Alignment on a partial line\n\n")
	b.WriteString("The last line is short, so the hex columns are padded and the ASCII ")
	b.WriteString("gutter stays put — that alignment is the whole point of the layout.\n\n")
	dump("0123456789abcdefhi", &b)

	b.WriteString("\n## What a rendered string hides\n\n")
	b.WriteString("These two look identical in any UI:\n\n")
	b.WriteString("- `\"hi\"`\n- `\"hi \"` — one trailing space\n\n")
	dump("hi", &b)
	b.WriteString("\n")
	dump("hi ", &b)

	b.WriteString("\n## Multi-byte UTF-8\n\n")
	b.WriteString("`\"café\"` is 5 bytes, not 4: `é` is `c3 a9`. Non-printables render as `.`.\n\n")
	dump("café", &b)

	b.WriteString("\n## Control characters\n\n")
	b.WriteString("A NUL, a newline and a tab are invisible in text and obvious here.\n\n")
	out, n := hexdump.Dump([]byte{0x00, 0x0a, 0x09, 'o', 'k'})
	b.WriteString("```\n" + out + "```\n\n")
	b.WriteString("_" + strconv.Itoa(n) + " bytes._\n")
	return b.String()
}

func dump(s string, b *strings.Builder) {
	out, n := hexdump.DumpString(s)
	b.WriteString("```\n" + out + "```\n")
	b.WriteString("\n_`" + s + "` → " + strconv.Itoa(n) + " bytes._\n")
}
