// Package sparklinedemo is a small gnoweb demo of the block-character series
// renderer provided by the [p/moul/x/daily/sparkline](/p/moul/x/daily/sparkline/v0)
// library: it sparks a few fixed series and shows the three behaviours worth
// knowing before using it in a realm — flat series, clamping, and floor
// rounding.
//
// It contains no rendering logic of its own. Stateless, so Render is
// deterministic.
package sparklinedemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/x/daily/sparkline/v0"
)

// series are fixed rather than derived from chain state: a demo whose output
// moved with the block height could not be pinned by an example test.
var (
	traffic = []int{3, 5, 9, 14, 12, 18, 25, 21, 16, 11, 7, 4}
	flat    = []int{1000, 1000, 1000, 1000}
	swing   = []int{-8, -3, 0, 4, 9, 2, -5}
	pct     = []int{-20, 0, 25, 50, 75, 100, 140}
)

// Render renders the demo for gnoweb.
//
//	Render("") / Render("/") -> the full demo
func Render(path string) string {
	var b strings.Builder

	b.WriteString("# Sparklines\n\n")
	b.WriteString("A numeric series as one line of block characters, demoing the ")
	b.WriteString("[`p/moul/x/daily/sparkline`](/p/moul/x/daily/sparkline/v0) library.\n\n")

	b.WriteString("## A series\n\n")
	lo, hi, _ := sparkline.Bounds(traffic)
	b.WriteString("`" + sparkline.Ints(traffic) + "`\n\n")
	b.WriteString(ints(traffic) + "\n\n")
	b.WriteString("Scaled between its own bounds, `" + strconv.Itoa(lo) + "` and `" +
		strconv.Itoa(hi) + "`. The shape is the point; the axis is not.\n\n")

	b.WriteString("## The ramp\n\n")
	b.WriteString("`" + sparkline.Levels + "` — eight levels, low to high.\n\n")
	b.WriteString("| value | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |\n")
	b.WriteString("|---|---|---|---|---|---|---|---|---|\n")
	b.WriteString("| level |")
	for v := 0; v <= 7; v++ {
		b.WriteString(" `" + sparkline.Scaled([]int{v}, 0, 7) + "` |")
	}
	b.WriteString("\n\n")

	b.WriteString("## A flat series\n\n")
	b.WriteString("`" + sparkline.Ints(flat) + "` — " + ints(flat) + "\n\n")
	b.WriteString("Mid-ramp, not along the floor. A series that never moves has no ")
	b.WriteString("shape, but drawing it at the bottom would claim it was *zero*, ")
	b.WriteString("which is a different thing and a wrong one.\n\n")

	b.WriteString("## Negatives\n\n")
	b.WriteString("`" + sparkline.Ints(swing) + "` — " + ints(swing) + "\n\n")
	b.WriteString("Nothing special: the window is the minimum and maximum, wherever ")
	b.WriteString("zero happens to fall.\n\n")

	b.WriteString("## A fixed window clamps\n\n")
	b.WriteString(ints(pct) + " against `0..100`:\n\n")
	b.WriteString("`" + sparkline.Scaled(pct, 0, 100) + "`\n\n")
	b.WriteString("`-20` pins to the floor and `140` to the ceiling. Choosing the ")
	b.WriteString("window keeps a percentage readable, and one outlier cannot flatten ")
	b.WriteString("the rest of the picture — or break the realm that drew it.\n\n")

	b.WriteString("## Rounding is floor\n\n")
	b.WriteString("| value in `0..100` | level |\n")
	b.WriteString("|---|---|\n")
	for _, v := range []int{0, 14, 50, 85, 99, 100} {
		b.WriteString("| " + strconv.Itoa(v) + " | `" +
			sparkline.Scaled([]int{v}, 0, 100) + "` |\n")
	}
	b.WriteString("\nOnly the maximum itself reaches the top of the ramp, so the peak ")
	b.WriteString("of a series is always visually distinct.\n\n")

	b.WriteString("## Why integers\n\n")
	b.WriteString("Scaling is integer division throughout. Render output has to be ")
	b.WriteString("byte-identical on every validating node, and floating point is the ")
	b.WriteString("usual way that quietly stops being true.\n")

	return b.String()
}

// ints formats a series as `a, b, c` for the prose around each sparkline.
func ints(values []int) string {
	parts := make([]string, len(values))
	for i, v := range values {
		parts[i] = strconv.Itoa(v)
	}
	return "`" + strings.Join(parts, ", ") + "`"
}
