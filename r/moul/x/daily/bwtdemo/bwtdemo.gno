// Package bwtdemo is a small gnoweb demo of the Burrows-Wheeler transform
// provided by the [p/moul/x/daily/bwt](/p/moul/x/daily/bwt/v0) library: the
// rotation matrix the transform is read off, the round trip back, and what
// the clustering is actually worth on four inputs, including the one where it
// is worth nothing.
//
// It contains no transform logic of its own. Stateless, so Render is
// deterministic: every figure below is computed from the fixed strings at the
// top of this file, never from chain state, which is what lets an example
// test pin the page.
package bwtdemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/x/daily/bwt/v0"
)

// worked is the example small enough to check by hand: six bytes, three
// distinct, and a rotation matrix that fits on a screen.
const worked = "banana"

// samples show what the clustering is worth, and the last one shows that it
// is sometimes worth nothing. "mississippi" repeats letters but no substring
// long enough to group, so its run count does not move.
var samples = []string{
	"abracadabra abracadabra",
	"banana bandana bandanna",
	"the quick brown fox jumps over the lazy dog",
	"mississippi",
}

// Render renders the demo for gnoweb.
//
//	Render("") / Render("/") -> the worked example, the ratios, the round trip
//	Render("/<text>")        -> transform that text
func Render(path string) string {
	if in := parseArg(path); in != "" {
		return renderInput(in)
	}

	var b strings.Builder
	b.WriteString("# Burrows-Wheeler transform\n\n")
	b.WriteString("A reversible permutation that groups equal bytes together, demoing ")
	b.WriteString("the [`p/moul/x/daily/bwt`](/p/moul/x/daily/bwt/v0) library. ")
	b.WriteString("It compresses nothing on its own: the output holds the same bytes ")
	b.WriteString("as the input in a different order, and the clustering is what a ")
	b.WriteString("run-length or entropy coder downstream gets paid by.\n\n")

	b.WriteString("## The matrix, for `" + worked + "`\n\n")
	b.WriteString("Every rotation of the input, sorted. The transform is the **last ")
	b.WriteString("column** read downwards, and the second value is the row the input ")
	b.WriteString("itself landed on.\n\n")

	rows, primary, err := bwt.Matrix(worked)
	if err != nil {
		return b.String() + "> " + err.Error() + "\n"
	}
	t := ui.NewTable("row", "rotation", "last byte")
	for i, r := range rows {
		label := strconv.Itoa(i)
		if i == primary {
			label = "**" + label + "**"
		}
		t.Row(label, "`"+r+"`", "`"+string(r[len(r)-1])+"`")
	}
	b.WriteString(t.String() + "\n")

	last, idx, err := bwt.Transform(worked)
	if err != nil {
		return b.String() + "> " + err.Error() + "\n"
	}
	b.WriteString("So `" + worked + "` transforms to `" + last + "`, row **")
	b.WriteString(strconv.Itoa(idx) + "**.\n\n")

	b.WriteString("## Getting it back\n\n")
	b.WriteString("`Inverse` never rebuilds that matrix. The first column is the last ")
	b.WriteString("one sorted, and the *i*-th occurrence of a byte in the last column ")
	b.WriteString("is the *i*-th occurrence of it in the first, which is enough to ")
	b.WriteString("walk the original backwards one byte at a time:\n\n")
	back, err := bwt.Inverse(last, idx)
	if err != nil {
		return b.String() + "> " + err.Error() + "\n"
	}
	b.WriteString("```\nInverse(\"" + last + "\", " + strconv.Itoa(idx) + ") = \"" + back + "\"\n```\n\n")
	if back == worked {
		b.WriteString("Same bytes, original order. ✅\n\n")
	} else {
		b.WriteString("Something is wrong: that is not the input. ❌\n\n")
	}
	b.WriteString("The index is what lets the transform avoid a sentinel byte. A ")
	b.WriteString("sentinel has to be a byte the input can never contain, and in an ")
	b.WriteString("arbitrary string there is no such byte.\n\n")

	b.WriteString("## What the clustering is worth\n\n")
	st := ui.NewTable("input", "runs", "transformed", "runs")
	for _, s := range samples {
		l, _, err := bwt.Transform(s)
		if err != nil {
			continue
		}
		st.Row(
			md.InlineCode(s),
			strconv.Itoa(bwt.Runs(s)),
			md.InlineCode(l),
			strconv.Itoa(bwt.Runs(l))+" "+verdict(bwt.Runs(s), bwt.Runs(l)),
		)
	}
	b.WriteString(st.String() + "\n")
	b.WriteString("Fewer runs over the same length means longer runs, and a ")
	b.WriteString("run-length coder is paid by run length. `mississippi` is the ")
	b.WriteString("honest counter-example: it repeats letters but no substring long ")
	b.WriteString("enough to group, so the transform buys nothing at all. The ")
	b.WriteString("clustering is a tendency, never a guarantee, which is why `Runs` ")
	b.WriteString("is exported: measure it instead of assuming it.\n\n")

	b.WriteString("## Try your own\n\n")
	b.WriteString("```\n/r/moul/x/daily/bwtdemo/v0:banana bandana\n```\n")
	return b.String()
}

// renderInput transforms a caller's text. Everything echoed back goes through
// md.InlineCode or ui.Cell: the string arrives from the URL and is attacker
// controlled markdown until it is escaped. The transformed string needs it
// just as much, because it is a permutation of the caller's own bytes and
// carries every backtick and pipe straight through.
func renderInput(in string) string {
	var b strings.Builder
	b.WriteString("# Burrows-Wheeler transform\n\n")
	b.WriteString("Input: " + md.InlineCode(in) + "\n\n")

	last, idx, err := bwt.Transform(in)
	if err != nil {
		b.WriteString("> " + ui.Inline(err.Error()) + "\n")
		return b.String()
	}
	back, err := bwt.Inverse(last, idx)
	if err != nil {
		b.WriteString("> " + ui.Inline(err.Error()) + "\n")
		return b.String()
	}

	// ui.Cell, not md.InlineCode: a code span escapes nothing a table cares
	// about, so a pipe in the caller's input survives into the cell and opens
	// a column. The transformed string is a permutation of their bytes, which
	// means it carries every pipe and backtick they sent.
	t := ui.NewTable("field", "value")
	t.Row("transformed", ui.Cell(last))
	t.Row("index", strconv.Itoa(idx))
	t.Row("runs", strconv.Itoa(bwt.Runs(in))+" → "+strconv.Itoa(bwt.Runs(last))+
		" "+verdict(bwt.Runs(in), bwt.Runs(last)))
	t.Row("round-trips", roundTrip(back == in))
	b.WriteString(t.String() + "\n")

	if rows, primary, err := bwt.Matrix(in); err == nil {
		b.WriteString("### The matrix\n\n")
		mt := ui.NewTable("row", "rotation", "last byte")
		for i, r := range rows {
			label := strconv.Itoa(i)
			if i == primary {
				label = "**" + label + "**"
			}
			mt.Row(label, ui.Cell(r), ui.Cell(string(r[len(r)-1])))
		}
		b.WriteString(mt.String() + "\n")
	} else {
		b.WriteString("The matrix is only shown up to " +
			strconv.Itoa(bwt.MaxMatrixLen) + " bytes: it holds every rotation at " +
			"once, n squared bytes of them, while the transform compares rotations " +
			"in place and holds only n. Both do the same quadratic amount of " +
			"comparing; it is the memory that differs.\n\n")
	}

	b.WriteString("[back](/r/moul/x/daily/bwtdemo/v0)\n")
	return b.String()
}

// verdict labels a run count against the one it came from, so the table says
// what happened rather than leaving two numbers side by side.
func verdict(before, after int) string {
	switch {
	case after < before:
		return "✅"
	case after > before:
		return "❌"
	}
	return "="
}

func roundTrip(ok bool) string {
	if ok {
		return "✅"
	}
	return "❌"
}

// parseArg takes the one routing slash off and nothing else. It does not trim:
// the transform is byte-preserving, so a page that silently dropped the
// caller's leading or trailing spaces would show the result of transforming a
// string they never sent, and "   " would be mistaken for the root page.
func parseArg(path string) string {
	return strings.TrimPrefix(path, "/")
}
