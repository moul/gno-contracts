// Package hyperloglogdemo is a small gnoweb demo of the cardinality estimator
// provided by the [p/moul/x/daily/hyperloglog](/p/moul/x/daily/hyperloglog/v0)
// library: how close a kilobyte of registers gets to the true number of
// distinct elements, what that kilobyte buys at each precision, and the merge
// that counts a union without shipping either side's elements.
//
// It contains no estimation logic of its own. Stateless, so Render is
// deterministic: every figure below is computed from the generated element
// sets declared at the top of this file, never from chain state, which is what
// lets an example test pin the page.
package hyperloglogdemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/x/daily/hyperloglog/v0"
)

// sizes are the cardinalities the accuracy table walks, chosen to straddle the
// switch between the two estimators: the first three sit in the small range
// where linear counting still answers exactly, the last two are past it.
var sizes = []int{1, 10, 100, 1000, 5000}

// precisions are the sizes the space table compares. 10 is the library
// default and the one every other figure on this page uses.
var precisions = []int{4, 8, 10, 12, 14, 16}

// The two shards of the merge example. They overlap by half, which is the
// only way to show that a union is not a sum.
const (
	leftFirst, leftCount   = 0, 1000
	rightFirst, rightCount = 500, 1000
	unionCount             = 1500
)

// Render renders the demo for gnoweb.
//
//	Render("") / Render("/") -> the full demo
func Render(path string) string {
	var b strings.Builder

	b.WriteString("# HyperLogLog\n\n")
	b.WriteString("How many DISTINCT elements a stream contained, out of a ")
	b.WriteString("fixed kilobyte that never grows, demoing the ")
	b.WriteString("[`p/moul/x/daily/hyperloglog`](/p/moul/x/daily/hyperloglog/v0) ")
	b.WriteString("library.\n\n")
	b.WriteString("Counting unique callers with a set costs one stored object ")
	b.WriteString("per caller, and nobody in the realm decides how many ")
	b.WriteString("callers there will be. This costs 1,024 bytes at ten ")
	b.WriteString("elements and 1,024 bytes at ten million.\n\n")

	b.WriteString("## Three sketches, three questions\n\n")
	ft := ui.NewTable("question", "structure", "what it cannot do")
	ft.Row("have I seen this one?",
		"[bloom filter](/r/moul/x/daily/bloomfilter)",
		"tell you how many there were")
	ft.Row("how often did this one arrive?",
		"[count-min sketch](/p/moul/x/daily/countminsketch/v0)",
		"tell you how many were different")
	ft.Row("how many different ones were there?",
		"**this one**",
		"tell you whether it has seen YOU")
	b.WriteString(ft.String() + "\n")
	b.WriteString("The third is the one most easily misread. A sketch that ")
	b.WriteString("has counted a million elements holds none of them: only ")
	b.WriteString("the longest run of leading zeros each register was ever ")
	b.WriteString("shown. That is why it fits in a kilobyte, and why nothing ")
	b.WriteString("can be taken back out.\n\n")

	b.WriteString("## How close it gets\n\n")
	b.WriteString("Every row below is a fresh sketch at the default ")
	b.WriteString("precision: " + strconv.Itoa(hyperloglog.DefaultPrecision))
	b.WriteString(", so " + strconv.Itoa(hyperloglog.NewDefault().Registers()))
	b.WriteString(" registers and a standard error of ")
	b.WriteString(errPct(hyperloglog.NewDefault()) + ".\n\n")
	at := ui.NewTable("true count", "estimate", "off by", "error", "registers used", "estimator")
	for _, n := range sizes {
		s := hyperloglog.NewDefault()
		for i := 0; i < n; i++ {
			s.Add("caller-" + strconv.Itoa(i))
		}
		got := s.Count()
		off := got - int64(n)
		at.Row(
			strconv.Itoa(n),
			strconv.FormatInt(got, 10),
			signed(off),
			pct(off, int64(n)),
			strconv.Itoa(s.Registers()-s.Zeros())+" of "+strconv.Itoa(s.Registers()),
			estimator(s),
		)
	}
	b.WriteString(at.String() + "\n")
	b.WriteString("Two estimators, and the switch between them is where naive ")
	b.WriteString("implementations go wrong. While most registers are still ")
	b.WriteString("empty the answer comes from counting the empty ones, which ")
	b.WriteString("is exact until two elements collide. Once they are mostly ")
	b.WriteString("full the harmonic mean of the registers takes over, and ")
	b.WriteString("the answer becomes an estimate with a published error bar ")
	b.WriteString("rather than a number.\n\n")

	b.WriteString("## What the kilobyte buys\n\n")
	st := ui.NewTable("precision", "registers", "bytes", "standard error")
	for _, p := range precisions {
		s, err := hyperloglog.New(p)
		if err != nil {
			continue
		}
		label := "`" + strconv.Itoa(p) + "`"
		if p == hyperloglog.DefaultPrecision {
			label += " (default)"
		}
		st.Row(label, strconv.Itoa(s.Registers()), strconv.Itoa(s.Bytes()), errPct(s))
	}
	b.WriteString(st.String() + "\n")
	b.WriteString("The error does not depend on the cardinality, only on the ")
	b.WriteString("register count, which is the counter-intuitive part: the ")
	b.WriteString("same kilobyte is about as wrong at a thousand elements as ")
	b.WriteString("at a billion. Halving the error costs four times the ")
	b.WriteString("space, so the useful range is narrow and the default sits ")
	b.WriteString("in the middle of it.\n\n")

	b.WriteString("## Merging two shards\n\n")
	b.WriteString("The operation no exact counter can offer without shipping ")
	b.WriteString("its elements. The two shards below overlap by 500, so a ")
	b.WriteString("sum would answer 2,000 and the union is 1,500.\n\n")
	left := shard("k", leftFirst, leftCount)
	right := shard("k", rightFirst, rightCount)
	merged := left.Clone()
	if err := merged.Merge(right); err != nil {
		// Unreachable: both shards are built here at the same precision.
		return b.String() + "merge failed: " + err.Error() + "\n"
	}
	mt := ui.NewTable("sketch", "elements added", "distinct", "estimate", "error")
	mt.Row("left shard", strconv.FormatInt(left.Adds(), 10), strconv.Itoa(leftCount),
		strconv.FormatInt(left.Count(), 10), pct(left.Count()-int64(leftCount), int64(leftCount)))
	mt.Row("right shard", strconv.FormatInt(right.Adds(), 10), strconv.Itoa(rightCount),
		strconv.FormatInt(right.Count(), 10), pct(right.Count()-int64(rightCount), int64(rightCount)))
	mt.Row("**merged**", strconv.FormatInt(merged.Adds(), 10), strconv.Itoa(unionCount),
		strconv.FormatInt(merged.Count(), 10), pct(merged.Count()-int64(unionCount), int64(unionCount)))
	b.WriteString(mt.String() + "\n")
	b.WriteString("A merge is a register-wise maximum, so an element present ")
	b.WriteString("in both shards has no way to be counted twice. That also ")
	b.WriteString("makes it idempotent: replaying the same merge changes ")
	b.WriteString("nothing, which matters when the shards are days of history ")
	b.WriteString("and somebody re-runs a job.\n\n")

	b.WriteString("## What it will not do\n\n")
	lt := ui.NewTable("limit", "behaviour", "why")
	lt.Row("membership", "not answerable", "no element is stored, only zero-run lengths")
	lt.Row("removal", "not supported", "a register is a maximum, and a maximum cannot be undone")
	lt.Row("exactness", "only in the small range", "past a few thousand it is an estimate with an error bar")
	lt.Row("the error bar", "one standard deviation", "about a third of sketches land outside it")
	lt.Row("precision", "`"+strconv.Itoa(hyperloglog.MinPrecision)+"` to `"+
		strconv.Itoa(hyperloglog.MaxPrecision)+"`",
		"below is noise, above buys a fraction of a percent for 64 KiB")
	b.WriteString(lt.String() + "\n")
	b.WriteString("A realm that needs the elements back needs a set and the ")
	b.WriteString("bill that comes with one. This is for the case where the ")
	b.WriteString("number was the whole question: unique callers this week, ")
	b.WriteString("distinct voters, how many addresses touched a pool.\n")

	return b.String()
}

// shard builds a sketch over count generated elements numbered from first.
func shard(prefix string, first, count int) *hyperloglog.Sketch {
	s := hyperloglog.NewDefault()
	for i := first; i < first+count; i++ {
		s.Add(prefix + strconv.Itoa(i))
	}
	return s
}

// estimator names which of the two branches produced a sketch's answer. It
// reads the same signal the library does, the number of registers still at
// zero, rather than being told.
func estimator(s *hyperloglog.Sketch) string {
	if s.Zeros() > s.Registers()/2 {
		return "linear counting"
	}
	return "harmonic mean"
}

// errPct renders a sketch's theoretical standard error. The float is turned
// into basis points immediately: `ufmt/v0` has no width flags, so a decimal
// place is assembled from integers or not at all.
func errPct(s *hyperloglog.Sketch) string {
	return pctBP(int64(s.RelativeError()*10000 + 0.5))
}

// signed renders an integer with an explicit sign, so a column of deltas lines
// up visually whichever way they went.
func signed(v int64) string {
	if v > 0 {
		return "+" + strconv.FormatInt(v, 10)
	}
	return strconv.FormatInt(v, 10)
}

// pct renders num/den as a signed percentage with two decimals.
func pct(num, den int64) string {
	if den == 0 {
		return "n/a"
	}
	bp := num * 10000 / den
	if bp < 0 {
		return "-" + pctBP(-bp)
	}
	return "+" + pctBP(bp)
}

// pctBP renders unsigned basis points as a percentage with two decimals.
func pctBP(bp int64) string {
	frac := strconv.FormatInt(bp%100, 10)
	if bp%100 < 10 {
		frac = "0" + frac
	}
	return strconv.FormatInt(bp/100, 10) + "." + frac + "%"
}
