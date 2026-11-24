// Package intervalsetdemo is a small gnoweb demo of the coalescing interval
// set provided by the
// [p/moul/x/daily/intervalset](/p/moul/x/daily/intervalset/v0) library: how a
// run of overlapping writes collapses to the shape of the data, where a
// half-open range starts and stops, and what a plain slice of pairs gets wrong.
//
// It contains no interval logic of its own. Stateless, so Render is
// deterministic: the page is replayed from the fixed script at the top of this
// file on every call, never from chain state, which is what lets an example
// test pin it.
package intervalsetdemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/x/daily/intervalset/v0"
)

// script is the worked example: a realm collecting booked slots, written in
// the order the bookings arrived rather than in any useful order. Nine writes
// that end up as two spans.
//
//	{lo, hi, remove}
var script = []op{
	{100, 150, false},
	{300, 400, false},
	{140, 210, false}, // overlaps the first
	{210, 260, false}, // only TOUCHES the previous one, and still merges
	{260, 300, false}, // bridges the gap to the second span
	{500, 520, false},
	{505, 515, false}, // already covered: changes nothing at all
	{180, 200, true},  // a cancellation in the middle, which splits
	{180, 200, false}, // and rebooking closes the hole again
}

type op struct {
	lo     int64
	hi     int64
	remove bool
}

// Render renders the demo for gnoweb.
//
//	Render("") / Render("/") -> the full demo
func Render(path string) string {
	var b strings.Builder

	b.WriteString("# Interval set\n\n")
	b.WriteString("Half-open ranges kept sorted, disjoint and coalesced, demoing ")
	b.WriteString("the [`p/moul/x/daily/intervalset`](/p/moul/x/daily/intervalset/v0) ")
	b.WriteString("library.\n\n")
	b.WriteString("A realm collecting booked slots, written in the order the ")
	b.WriteString("bookings arrived. Watch the **spans** column: it tracks the ")
	b.WriteString("shape of the data, not the number of writes.\n\n")

	s := intervalset.New()

	t := ui.NewTable("#", "write", "spans", "covered", "the set")
	for i, o := range script {
		if o.remove {
			s.Remove(o.lo, o.hi)
		} else {
			s.Add(o.lo, o.hi)
		}
		t.Row(strconv.Itoa(i+1),
			md.InlineCode(verb(o)),
			strconv.Itoa(s.Len()),
			strconv.FormatInt(s.Measure(), 10),
			md.InlineCode(s.String()))
	}
	b.WriteString(t.String() + "\n")

	b.WriteString("Nine writes, two spans. A slice of pairs appended to on every ")
	b.WriteString("write would hold nine, forever, and this is on chain: storage ")
	b.WriteString("is paid for once and kept for good.\n\n")

	b.WriteString("Row 4 is the one worth staring at. `[210,260)` does not overlap ")
	b.WriteString("`[100,210)`, it only touches it, and they still merge. Row 7 is ")
	b.WriteString("the opposite case: `[505,515)` is already inside `[500,520)`, so ")
	b.WriteString("it is not a write at all. Row 8 cancels from the middle, which is ")
	b.WriteString("the only operation here that can raise the span count.\n\n")

	b.WriteString("## Half-open, and why it matters here\n\n")
	b.WriteString("A span is `[Lo, Hi)`: `Lo` is covered and `Hi` is not. That is ")
	b.WriteString("exactly what lets two touching ranges merge without overlapping, ")
	b.WriteString("and it is the detail callers get wrong.\n\n")
	ct := ui.NewTable("query", "answer", "why")
	for _, probe := range []int64{99, 100, 209, 210, 400, 505} {
		ct.Row(md.InlineCode("Contains("+strconv.FormatInt(probe, 10)+")"),
			yesno(s.Contains(probe)),
			why(s, probe))
	}
	b.WriteString(ct.String() + "\n")

	b.WriteString("## Asking about a range, not a point\n\n")
	rt := ui.NewTable("query", "answer", "meaning")
	rt.Row(md.InlineCode("Covers(120, 180)"), yesno(s.Covers(120, 180)), "entirely inside one span")
	rt.Row(md.InlineCode("Covers(380, 420)"), yesno(s.Covers(380, 420)), "runs off the end of its span")
	rt.Row(md.InlineCode("Covers(100, 400)"), yesno(s.Covers(100, 400)), "exactly the span: `400` is excluded from both")
	rt.Row(md.InlineCode("Overlaps(380, 420)"), yesno(s.Overlaps(380, 420)), "shares `380..399` with the set")
	rt.Row(md.InlineCode("Overlaps(400, 500)"), yesno(s.Overlaps(400, 500)), "exactly the gap between the two spans")
	b.WriteString(rt.String() + "\n")
	b.WriteString("`Covers` and `Overlaps` are the two questions a realm actually ")
	b.WriteString("asks (may this booking go ahead, does it clash with anything), ")
	b.WriteString("and they are different questions. Both are `O(log n)` by binary ")
	b.WriteString("search over the spans, so a `Render` can call them freely.\n\n")

	b.WriteString("## What the obvious implementation gets wrong\n\n")
	wt := ui.NewTable("", "a slice of pairs", "this")
	wt.Row("storage after the script above", "9 entries", strconv.Itoa(s.Len())+" spans")
	wt.Row("growth", "with every write, forever", "with the shape of the data")
	wt.Row("is this point covered", "`O(n)` scan, slower on every write", "`O(log n)`")
	wt.Row("total covered length", "double-counts every overlap", md.InlineCode(strconv.FormatInt(s.Measure(), 10))+", counted once")
	b.WriteString(wt.String() + "\n")
	b.WriteString("The last row is the one that costs money: a realm billing for ")
	b.WriteString("covered time against an uncoalesced list charges twice for every ")
	b.WriteString("overlap, and nothing about the list looks wrong.\n")

	return b.String()
}

// verb spells one scripted write as the call that made it.
func verb(o op) string {
	name := "Add("
	if o.remove {
		name = "Remove("
	}
	return name + strconv.FormatInt(o.lo, 10) + ", " + strconv.FormatInt(o.hi, 10) + ")"
}

func yesno(b bool) string {
	if b {
		return "yes"
	}
	return "no"
}

// why explains one Contains answer in terms of the span nearest the probe.
func why(s *intervalset.Set, v int64) string {
	for _, sp := range s.Spans() {
		if sp.Lo == v {
			return "`Lo` of a span, and `Lo` is covered"
		}
		if sp.Hi == v {
			return "`Hi` of a span, and `Hi` is not"
		}
		if sp.Lo < v && v < sp.Hi {
			return "inside " + md.InlineCode("["+strconv.FormatInt(sp.Lo, 10)+","+strconv.FormatInt(sp.Hi, 10)+")")
		}
	}
	return "outside every span"
}
