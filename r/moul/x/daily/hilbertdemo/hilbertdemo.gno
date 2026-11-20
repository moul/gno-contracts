// Package hilbertdemo is a small gnoweb demo of the
// [p/moul/x/daily/hilbert](/p/moul/x/daily/hilbert/v0) library: it draws the
// curve, shows the index runs a box turns into, and compares those runs with
// what a row-major key would have cost.
//
// It contains no curve logic of its own. The only arithmetic here is the
// row-major baseline on the last page, which is the thing being compared
// against and deliberately not part of the library.
//
// Stateless and read-only, with fixed inputs, so Render is fully
// deterministic and takes nothing from a caller.
package hilbertdemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/x/daily/hilbert/v0"
)

// Fixed inputs. Nothing here depends on the chain, the clock or the caller,
// which is what lets an example test pin every page.
const (
	curveOrder = 3 // the drawn curve: 8x8, small enough to read

	boxOrder               = 4 // the drawn box: 16x16
	boxX0, boxY0           = 6, 6
	boxX1, boxY1           = 13, 13
	alignedX0, alignedY0   = 8, 8
	alignedX1, alignedY1   = 15, 15

	keyOrder = 16 // a realistic grid: 65536 on a side, 4.29 billion cells
)

// Render renders the demo for gnoweb.
//
//	Render("") / Render("/")  -> the curve itself, drawn
//	Render("/box")            -> a box, and the index runs it becomes
//	Render("/keys")           -> the same question on a realistic grid
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# Hilbert curve\n\n")
	b.WriteString("Turning a point on a grid into one number that keeps neighbours ")
	b.WriteString("together, demoing the [`p/moul/x/daily/hilbert`](/p/moul/x/daily/hilbert/v0) library.\n\n")

	switch parseArg(path) {
	case "box":
		b.WriteString(renderBox())
	case "keys":
		b.WriteString(renderKeys())
	default:
		b.WriteString(renderCurve())
	}
	return b.String()
}

// renderCurve draws the order 3 curve as the index sitting in each cell, which
// makes the defining property visible: walk 0, 1, 2, ... and you never jump.
func renderCurve() string {
	var b strings.Builder
	side := hilbert.Side(curveOrder)
	b.WriteString("## The curve, at order " + strconv.Itoa(curveOrder) + "\n\n")
	b.WriteString("Each cell holds its index. Follow 0, 1, 2, 3 and you walk to a ")
	b.WriteString("neighbouring cell every single time, never across the grid.\n\n```\n")
	for y := int(side) - 1; y >= 0; y-- {
		row := make([]string, 0, int(side))
		for x := 0; x < int(side); x++ {
			d, err := hilbert.Encode(curveOrder, uint32(x), uint32(y))
			if err != nil {
				return b.String() + "```\n_unexpected error: " + err.Error() + "_\n"
			}
			row = append(row, pad(strconv.FormatUint(d, 10), 2))
		}
		b.WriteString("y=" + strconv.Itoa(y) + "  " + strings.Join(row, " ") + "\n")
	}
	b.WriteString("      " + axis(int(side)) + "\n```\n\n")
	b.WriteString("Interleaving the bits of x and y, which is what a geohash does, also ")
	b.WriteString("turns a point into one number. It jumps: at every power-of-two ")
	b.WriteString("boundary two neighbouring cells land far apart in the key space. ")
	b.WriteString("This curve never does, and every aligned sub-square of it is one ")
	b.WriteString("unbroken run of indices.\n\n")
	b.WriteString("> Next: [`/box`](/r/moul/x/daily/hilbertdemo/v0:box) for the runs a ")
	b.WriteString("box becomes, [`/keys`](/r/moul/x/daily/hilbertdemo/v0:keys) for what ")
	b.WriteString("that is worth on a real grid.\n")
	return b.String()
}

// renderBox draws a box on the order 4 grid and lists the runs it covers,
// which is the shape a caller hands to a tree iteration.
func renderBox() string {
	var b strings.Builder
	b.WriteString("## A box is a few runs of indices\n\n")
	b.WriteString("An avl tree has one key, and a map has two dimensions. Keying the ")
	b.WriteString("tree by the curve index makes \"everything inside this box\" a short ")
	b.WriteString("list of range scans, storing no geometry and computing no distance.\n\n")

	b.WriteString(grid(boxOrder, boxX0, boxY0, boxX1, boxY1))
	rs, err := hilbert.Ranges(boxOrder, boxX0, boxY0, boxX1, boxY1)
	if err != nil {
		return b.String() + "_unexpected error: " + err.Error() + "_\n"
	}
	b.WriteString("\nThe box " + boxLabel(boxX0, boxY0, boxX1, boxY1) + " covers ")
	b.WriteString(plural(len(rs), "run", "runs") + ":\n\n```\n")
	for _, r := range rs {
		b.WriteString(strconv.FormatUint(r.Lo, 10) + " .. " + strconv.FormatUint(r.Hi, 10) + "\n")
	}
	b.WriteString("```\n\n")
	b.WriteString("Every index in those runs is inside the box and every cell of the ")
	b.WriteString("box is in one of them, so a scan reads nothing it has to filter out.\n\n")

	aligned, err := hilbert.Ranges(boxOrder, alignedX0, alignedY0, alignedX1, alignedY1)
	if err != nil {
		return b.String() + "_unexpected error: " + err.Error() + "_\n"
	}
	b.WriteString("Move the same 8x8 box onto a power-of-two boundary, ")
	b.WriteString(boxLabel(alignedX0, alignedY0, alignedX1, alignedY1) + ", and it collapses to ")
	b.WriteString(plural(len(aligned), "run", "runs") + ": ")
	b.WriteString(strconv.FormatUint(aligned[0].Lo, 10) + " .. ")
	b.WriteString(strconv.FormatUint(aligned[0].Hi, 10) + ". An aligned sub-square is ")
	b.WriteString("always exactly one run, at every order.\n\n")
	b.WriteString("> Next: [`/keys`](/r/moul/x/daily/hilbertdemo/v0:keys) for the same ")
	b.WriteString("question on a grid worth storing.\n")
	return b.String()
}

// renderKeys is the honest comparison. At this size the box is a sliver of the
// grid rather than half of it, and that is where the curve earns its keep.
func renderKeys() string {
	var b strings.Builder
	side := hilbert.Side(keyOrder)
	b.WriteString("## What it is worth on a real grid\n\n")
	b.WriteString("Order " + strconv.Itoa(keyOrder) + ": " + strconv.FormatUint(uint64(side), 10))
	b.WriteString(" cells on a side, " + strconv.FormatUint(hilbert.Length(keyOrder), 10))
	b.WriteString(" in total. Three 16x16 windows, against the obvious alternative of ")
	b.WriteString("a row-major key, `y*side + x`:\n\n")
	t := ui.NewTable("window", "runs", "keys spanned", "row-major runs", "row-major keys spanned")
	for _, w := range [][4]uint32{
		{20000, 20000, 20015, 20015},
		{1000, 2000, 1015, 2015},
		{0, 0, 15, 15},
	} {
		rs, err := hilbert.Ranges(keyOrder, w[0], w[1], w[2], w[3])
		if err != nil {
			return b.String() + "_unexpected error: " + err.Error() + "_\n"
		}
		span := rs[len(rs)-1].Hi - rs[0].Lo + 1
		rows := uint64(w[3]-w[1]) + 1
		rowSpan := uint64(w[3]-w[1])*uint64(side) + uint64(w[2]-w[0]) + 1
		t.Row(
			boxLabel(w[0], w[1], w[2], w[3]),
			strconv.Itoa(len(rs)),
			strconv.FormatUint(span, 10),
			strconv.FormatUint(rows, 10),
			strconv.FormatUint(rowSpan, 10),
		)
	}
	b.WriteString(t.String())
	b.WriteString("\nA row-major key puts one row of the grid next to the next row, so a ")
	b.WriteString("window 16 rows tall always spans 15 whole rows of key space, however ")
	b.WriteString("narrow it is. The curve spans something closer to the area of the ")
	b.WriteString("window, because it never leaves a neighbourhood before finishing it.\n\n")
	b.WriteString("**It is not free and it is not always better.** On a grid barely ")
	b.WriteString("bigger than the box, a badly placed window costs more runs than ")
	b.WriteString("row-major would: at order 4 the window (5,5)-(10,10) is 9 runs ")
	b.WriteString("against row-major's 6. The curve pays off when the window is small ")
	b.WriteString("against the grid, which is the case a spatial index is for.\n\n")
	b.WriteString("> Back to [the curve](/r/moul/x/daily/hilbertdemo/v0) or ")
	b.WriteString("[the box](/r/moul/x/daily/hilbertdemo/v0:box).\n")
	return b.String()
}

// grid draws an order n grid with the cells of a box marked, so the shape the
// runs come from is visible rather than asserted.
func grid(order int, x0, y0, x1, y1 uint32) string {
	var b strings.Builder
	side := int(hilbert.Side(order))
	b.WriteString("```\n")
	for y := side - 1; y >= 0; y-- {
		row := make([]byte, 0, side)
		for x := 0; x < side; x++ {
			if uint32(x) >= x0 && uint32(x) <= x1 && uint32(y) >= y0 && uint32(y) <= y1 {
				row = append(row, '#')
				continue
			}
			row = append(row, '.')
		}
		b.WriteString(pad(strconv.Itoa(y), 2) + "  " + string(row) + "\n")
	}
	b.WriteString("```\n")
	return b.String()
}

// axis labels the x coordinates under a drawn grid.
func axis(side int) string {
	cols := make([]string, 0, side)
	for x := 0; x < side; x++ {
		cols = append(cols, pad(strconv.Itoa(x), 2))
	}
	return strings.Join(cols, " ")
}

func boxLabel(x0, y0, x1, y1 uint32) string {
	return "(" + strconv.FormatUint(uint64(x0), 10) + "," + strconv.FormatUint(uint64(y0), 10) +
		")-(" + strconv.FormatUint(uint64(x1), 10) + "," + strconv.FormatUint(uint64(y1), 10) + ")"
}

func plural(n int, one, many string) string {
	if n == 1 {
		return "1 " + one
	}
	return strconv.Itoa(n) + " " + many
}

// pad right-aligns s in a field of width w. ufmt/v0 has no width flags, so a
// table that lines up is built here rather than formatted.
func pad(s string, w int) string {
	for len(s) < w {
		s = " " + s
	}
	return s
}

// parseArg takes the first path element, which is all this demo routes on. It
// is never rendered back, so no caller string reaches the page.
func parseArg(path string) string {
	p := strings.TrimPrefix(path, "/")
	if i := strings.Index(p, "/"); i >= 0 {
		p = p[:i]
	}
	return strings.TrimSpace(p)
}
