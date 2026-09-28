// Package fenwickdemo is a small gnoweb demo of the Binary Indexed Tree
// provided by the [p/moul/x/daily/fenwick](/p/moul/x/daily/fenwick/v0)
// library: prefix sums, range queries, the internal ranges that make the
// structure legible, and the weighted draw that is the reason to use one.
//
// It contains no tree logic of its own. Stateless, so Render is deterministic:
// every figure below is computed from the fixed tables at the top of this file,
// never from chain state, which is what lets an example test pin the page.
package fenwickdemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/x/daily/fenwick/v0"
)

// scores is the worked example: eight slots, small enough to check by hand.
var scores = []int64{3, 1, 4, 1, 5, 9, 2, 6}

// stakes is the weighted-draw example. The zero is the interesting entry: a
// holder with no stake must never be drawn, and that is a property of the
// search, not of the caller remembering to skip them.
var (
	holders = []string{"alice", "bob", "carol", "dave", "erin"}
	stakes  = []int64{30, 0, 45, 5, 20}
)

// Render renders the demo for gnoweb.
//
//	Render("") / Render("/") -> the full demo
func Render(path string) string {
	var b strings.Builder

	b.WriteString("# Fenwick tree\n\n")
	b.WriteString("A Binary Indexed Tree: prefix sums and point updates both in ")
	b.WriteString("`O(log n)`, demoing the ")
	b.WriteString("[`p/moul/x/daily/fenwick`](/p/moul/x/daily/fenwick/v0) library.\n\n")

	tr := fenwick.FromSlice(scores)

	b.WriteString("## The values\n\n")
	b.WriteString("`" + joinInts(scores) + "` — " + strconv.Itoa(tr.Len()))
	b.WriteString(" slots totalling `" + strconv.FormatInt(tr.Total(), 10) + "`.\n\n")

	b.WriteString("## Prefix sums\n\n")
	pt := ui.NewTable("i", "value", "Prefix(i+1)")
	for i := 0; i < tr.Len(); i++ {
		pt.Row(strconv.Itoa(i),
			strconv.FormatInt(tr.At(i), 10),
			strconv.FormatInt(tr.Prefix(i+1), 10))
	}
	b.WriteString(pt.String() + "\n")

	b.WriteString("## Range queries\n\n")
	rt := ui.NewTable("call", "meaning", "result")
	rt.Row("`Range(2, 5)`", "slots 2, 3, 4", strconv.FormatInt(tr.Range(2, 5), 10))
	rt.Row("`Range(0, 8)`", "everything", strconv.FormatInt(tr.Range(0, 8), 10))
	rt.Row("`Range(5, 5)`", "empty", strconv.FormatInt(tr.Range(5, 5), 10))
	rt.Row("`Range(-9, 99)`", "clamped to the ends", strconv.FormatInt(tr.Range(-9, 99), 10))
	b.WriteString(rt.String() + "\n")
	b.WriteString("Reads clamp instead of panicking. A realm cannot be redeployed on ")
	b.WriteString("the same path, so a `Render` that panics on an out-of-range index ")
	b.WriteString("is a page that is broken for good. Writes do panic: a bad `Add` is ")
	b.WriteString("a transaction, and aborting it is the useful answer.\n\n")

	b.WriteString("## What the tree actually stores\n\n")
	b.WriteString("The array is not a copy of the values. Each internal slot holds the ")
	b.WriteString("sum of a run of them, and the run lengths are the powers of two in ")
	b.WriteString("the index. That is the whole trick, and `Covers` makes it visible.\n\n")
	ct := ui.NewTable("node", "covers slots", "sum")
	for i := 1; i <= tr.Len(); i++ {
		lo, hi := tr.Covers(i)
		ct.Row(strconv.Itoa(i),
			"`["+strconv.Itoa(lo)+", "+strconv.Itoa(hi)+")`",
			strconv.FormatInt(tr.Range(lo, hi), 10))
	}
	b.WriteString(ct.String() + "\n")
	b.WriteString("A prefix walk visits one node per set bit of the index, and those ")
	b.WriteString("nodes tile the prefix exactly: no gap, no overlap. Eight slots ")
	b.WriteString("means at most three nodes per query.\n\n")

	b.WriteString("## The weighted draw\n\n")
	b.WriteString("`SearchPrefix(target)` names the slot that owns a target drawn ")
	b.WriteString("below `Total`, in `O(log n)`. Each holder is picked in proportion ")
	b.WriteString("to their stake, and a zero stake can never be picked at all.\n\n")
	st := fenwick.FromSlice(stakes)
	wt := ui.NewTable("holder", "stake", "owns targets", "share")
	for i, h := range holders {
		lo := st.Prefix(i)
		hi := st.Prefix(i + 1)
		owns := "none"
		if hi > lo {
			owns = "`[" + strconv.FormatInt(lo, 10) + ", " + strconv.FormatInt(hi, 10) + ")`"
		}
		wt.Row(ui.Cell(h),
			strconv.FormatInt(stakes[i], 10),
			owns,
			pct(stakes[i], st.Total()))
	}
	b.WriteString(wt.String() + "\n")

	dt := ui.NewTable("target", "SearchPrefix", "holder")
	for _, target := range []int64{0, 29, 30, 74, 99} {
		i := st.SearchPrefix(target)
		dt.Row(strconv.FormatInt(target, 10), strconv.Itoa(i), ui.Cell(holders[i]))
	}
	b.WriteString(dt.String() + "\n")
	b.WriteString("Note target `30`: it is the first one past alice's share, and it ")
	b.WriteString("skips bob entirely rather than landing on a holder with nothing ")
	b.WriteString("staked. The search steps over zero-weight slots because their ")
	b.WriteString("prefix does not advance, not because anything checks for them.\n\n")

	b.WriteString("## Why not a plain slice\n\n")
	b.WriteString("Two obvious implementations each win one column and lose another. ")
	b.WriteString("A realm whose scoreboard is written by every player and read by ")
	b.WriteString("every page view pays both costs, which is where the middle row ")
	b.WriteString("earns its keep.\n\n")
	xt := ui.NewTable("structure", "point update", "prefix sum", "weighted draw")
	xt.Row("plain slice", "`O(1)`", "`O(n)`", "`O(n)`")
	xt.Row("**Fenwick tree**", "`O(log n)`", "`O(log n)`", "`O(log n)`")
	xt.Row("running totals", "`O(n)`", "`O(1)`", "`O(log n)`")
	b.WriteString(xt.String() + "\n")
	b.WriteString("The tree also carries no storage overhead: it is exactly `n` ")
	b.WriteString("values, rearranged.\n")

	return b.String()
}

// joinInts formats a slice for display. Written out rather than reached for
// from a library because there is no sensible shared home for it yet.
func joinInts(vals []int64) string {
	parts := make([]string, len(vals))
	for i, v := range vals {
		parts[i] = strconv.FormatInt(v, 10)
	}
	return strings.Join(parts, ", ")
}

// pct renders part/whole as a whole-number percentage.
//
// Integer arithmetic throughout: Render output has to be byte-identical on
// every validating node, and floating point is the usual way that stops being
// true.
func pct(part, whole int64) string {
	if whole == 0 {
		return "0%"
	}
	return strconv.FormatInt(part*100/whole, 10) + "%"
}
