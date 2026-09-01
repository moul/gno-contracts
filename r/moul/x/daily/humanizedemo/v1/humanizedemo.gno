// Package humanizedemo is a small gnoweb demo of the human-facing formatters
// provided by the [p/moul/x/daily/humanize](/p/moul/x/daily/humanize/v1)
// library: byte sizes, thousands separators, ordinals and block counts.
//
// It contains no formatting logic of its own. Stateless, so Render is
// deterministic.
package humanizedemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/x/daily/humanize/v1"
)

var sizes = []int64{0, 999, 1024, 1536, 1048576, 1073741824}
var counts = []int64{0, 1000, 1234567}
var ordinals = []int64{1, 2, 3, 11, 12, 13, 21, 101}
var blocks = []int64{0, 1, 15, 1234}

// Render renders the demo for gnoweb.
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# Humanize\n\n")
	b.WriteString("Integer-only formatting for people, demoing the ")
	b.WriteString("[`p/moul/x/daily/humanize`](/p/moul/x/daily/humanize/v1) library.\n\n")

	b.WriteString("## Bytes\n\n| n | rendered |\n|---|---|\n")
	for _, n := range sizes {
		row(&b, strconv.FormatInt(n, 10), humanize.Bytes(n))
	}

	b.WriteString("\n## Thousands\n\n| n | rendered |\n|---|---|\n")
	for _, n := range counts {
		row(&b, strconv.FormatInt(n, 10), humanize.Comma(n))
	}

	b.WriteString("\n## Ordinals\n\n")
	parts := []string{}
	for _, n := range ordinals {
		parts = append(parts, humanize.Ordinal(n))
	}
	b.WriteString("`" + strings.Join(parts, "` · `") + "`\n")
	b.WriteString("\n> 11th/12th/13th, not 11st/12nd/13rd — the teens are the trap.\n")

	b.WriteString("\n## Block counts\n\n| blocks | rendered |\n|---|---|\n")
	for _, n := range blocks {
		row(&b, strconv.FormatInt(n, 10), humanize.Blocks(n))
	}
	b.WriteString("\n> Deliberately vague, and in **blocks**: there is no wall clock ")
	b.WriteString("on chain, so \"about 2 hours\" would be a lie dressed as precision.\n")
	return b.String()
}

func row(b *strings.Builder, a, c string) {
	b.WriteString("| `")
	b.WriteString(a)
	b.WriteString("` | ")
	b.WriteString(c)
	b.WriteString(" |\n")
}
