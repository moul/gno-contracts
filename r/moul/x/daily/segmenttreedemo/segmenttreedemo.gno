// Package segmenttreedemo is a small gnoweb demo of the range structure
// provided by the [p/moul/x/daily/segmenttree](/p/moul/x/daily/segmenttree/v0)
// library: the same eight slots answered three different ways, the tree those
// answers are read off, and what a single write actually repairs.
//
// It contains no tree logic of its own. Stateless and read-only: every figure
// on the page is computed from the fixed slice at the top of this file and
// never from chain state, which is what lets an example test pin the output.
package segmenttreedemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/x/daily/segmenttree/v0"
)

// slots is the worked example: eight readings, small enough to check every
// answer by hand, with a repeated minimum so a point update has somewhere
// interesting to land.
var slots = []int64{3, 1, 4, 1, 5, 9, 2, 6}

// ranges are the windows the demo asks about. Half-open, like the library.
var ranges = [][2]int{
	{0, 8},
	{0, 4},
	{4, 8},
	{2, 6},
	{5, 6},
	{3, 3},
}

// Render renders the demo for gnoweb.
//
//	Render("") / Render("/") -> the slots, the three answers, the tree
//	Render("/update")        -> what one write changes, and what it does not
func Render(path string) string {
	var b strings.Builder

	b.WriteString("# Segment tree\n\n")
	b.WriteString("Sum, minimum and maximum over any window of the same slots, each in ")
	b.WriteString("`O(log n)`, with any single slot rewritable in `O(log n)` too. ")
	b.WriteString("Demoing the ")
	b.WriteString("[`p/moul/x/daily/segmenttree`](/p/moul/x/daily/segmenttree/v0) library.\n\n")

	if arg(path) == "update" {
		return b.String() + renderUpdate()
	}
	return b.String() + renderRoot()
}

// renderRoot shows the three trees over one slice, then the shape of one.
func renderRoot() string {
	var b strings.Builder

	b.WriteString("## The slots\n\n")
	b.WriteString("`" + join(slots) + "`, " + strconv.Itoa(len(slots)) + " of them.\n\n")

	sum := segmenttree.NewSum(slots)
	min := segmenttree.NewMin(slots)
	max := segmenttree.NewMax(slots)

	b.WriteString("## Three questions, one walk\n\n")
	t := ui.NewTable("window", "sum", "min", "max")
	for _, r := range ranges {
		t.Row(
			"`["+strconv.Itoa(r[0])+","+strconv.Itoa(r[1])+")`",
			answer(sum, r[0], r[1]),
			answer(min, r[0], r[1]),
			answer(max, r[0], r[1]),
		)
	}
	b.WriteString(t.String())
	b.WriteString("\nThe last row is empty, and the library says so rather than ")
	b.WriteString("returning the identity: `min` over no slots would otherwise read ")
	b.WriteString("`9223372036854775807`, which is a number a page should never print.\n\n")

	b.WriteString("## The tree the sums are read off\n\n")
	b.WriteString("```\n" + levels(sum) + "```\n\n")
	b.WriteString("Each node holds the sum of the range beside it, so a window is ")
	b.WriteString("answered by at most two nodes per level rather than by ")
	b.WriteString(strconv.Itoa(len(slots)) + " additions.\n\n")

	b.WriteString("> See [`/update`](/r/moul/x/daily/segmenttreedemo/v0:update) for ")
	b.WriteString("what one write repairs.\n")
	return b.String()
}

// renderUpdate shows a point update: what moves, and how little of the tree
// had to be touched for it to move.
func renderUpdate() string {
	var b strings.Builder

	const slot = 5
	const to = int64(0)

	min := segmenttree.NewMin(slots)
	sum := segmenttree.NewSum(slots)
	beforeMin, _ := min.Query(4, 8)
	beforeSum, _ := sum.Query(4, 8)

	b.WriteString("## One write\n\n")
	b.WriteString("Slot `" + strconv.Itoa(slot) + "` goes from `")
	b.WriteString(at(slots, slot) + "` to `" + strconv.FormatInt(to, 10) + "`.\n\n")

	min.Set(slot, to)
	sum.Set(slot, to)
	afterMin, _ := min.Query(4, 8)
	afterSum, _ := sum.Query(4, 8)

	t := ui.NewTable("window `[4,8)`", "before", "after")
	t.Row("sum", strconv.FormatInt(beforeSum, 10), strconv.FormatInt(afterSum, 10))
	t.Row("min", strconv.FormatInt(beforeMin, 10), strconv.FormatInt(afterMin, 10))
	b.WriteString(t.String())

	b.WriteString("\n## What it cost\n\n")
	b.WriteString("The tree is " + strconv.Itoa(sum.Depth()) + " levels deep, so the ")
	b.WriteString("write repaired " + strconv.Itoa(sum.Depth()-1) + " parent nodes and ")
	b.WriteString("left the other " + strconv.Itoa(len(sum.Nodes())-sum.Depth()) + " alone. ")
	b.WriteString("A prefix-sum array would have answered the window faster and then ")
	b.WriteString("rewritten every slot after this one.\n\n")

	b.WriteString("```\n" + levels(sum) + "```\n\n")
	b.WriteString("> Back to [the root page](/r/moul/x/daily/segmenttreedemo/v0).\n")
	return b.String()
}

// levels renders the tree one line per level, as "[lo,hi)=value" cells.
//
// Every line is right-trimmed: an example test cannot pin trailing whitespace,
// and padding the last cell of a line would produce exactly that.
func levels(t *segmenttree.Tree) string {
	lines := []string{}
	level := -1
	cur := ""
	for _, n := range t.Nodes() {
		if n.Level != level {
			if level >= 0 {
				lines = append(lines, strings.TrimRight(cur, " "))
			}
			level = n.Level
			cur = "L" + strconv.Itoa(level) + " "
		}
		cell := "[" + strconv.Itoa(n.Lo) + "," + strconv.Itoa(n.Hi) + ")=" +
			strconv.FormatInt(n.Value, 10)
		cur += pad(cell, 12)
	}
	if level >= 0 {
		lines = append(lines, strings.TrimRight(cur, " "))
	}
	return strings.Join(lines, "\n") + "\n"
}

// answer formats one query, naming an empty window instead of printing the
// identity the library hands back with it.
func answer(t *segmenttree.Tree, lo, hi int) string {
	v, ok := t.Query(lo, hi)
	if !ok {
		return "_empty_"
	}
	return strconv.FormatInt(v, 10)
}

// at formats one slot, for a sentence.
func at(values []int64, i int) string {
	if i < 0 || i >= len(values) {
		return "?"
	}
	return strconv.FormatInt(values[i], 10)
}

// join renders a slice as space-separated numbers.
func join(values []int64) string {
	parts := make([]string, len(values))
	for i, v := range values {
		parts[i] = strconv.FormatInt(v, 10)
	}
	return strings.Join(parts, " ")
}

// pad right-pads to width, which ufmt cannot do: p/nt/ufmt/v0 has no width
// flags and silently drops them.
func pad(s string, width int) string {
	if len(s) >= width {
		return s + " "
	}
	return s + strings.Repeat(" ", width-len(s))
}

// arg extracts the first path segment.
func arg(path string) string {
	s := strings.TrimSpace(path)
	s = strings.TrimPrefix(s, "/")
	if i := strings.IndexByte(s, '/'); i >= 0 {
		s = s[:i]
	}
	return s
}
