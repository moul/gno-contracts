// Package jarowinklerdemo is a small gnoweb demo of the Jaro and Jaro-Winkler
// string similarity metrics provided by the
// [p/moul/x/daily/jarowinkler](/p/moul/x/daily/jarowinkler/v0) library: it
// scores the classic record-linkage pairs, then opens one of them up and shows
// which runes matched, which arrived out of order, and how much the shared
// prefix was worth.
//
// It contains no scoring logic of its own. Stateless, so Render is
// deterministic.
package jarowinklerdemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/x/daily/jarowinkler/v0"
)

// vectors are the pairs the literature on Jaro-Winkler keeps coming back to,
// each one chosen for the thing it shows rather than for its score.
var vectors = [][3]string{
	{"MARTHA", "MARHTA", "one transposition, three shared leading runes"},
	{"DWAYNE", "DUANE", "different lengths, no transposition"},
	{"DIXON", "DICKSONX", "half of DICKSONX never matches"},
	{"CRATE", "TRACE", "under 0.7, so the prefix buys nothing"},
	{"JELLYFISH", "SMELLYFISH", "eight matches and no prefix at all"},
	{"gno", "gnoland", "a word against the word it starts"},
}

// explained is the pair the Inside section opens up.
var explained = [2]string{"MARTHA", "MARHTA"}

// Render renders the demo for gnoweb.
//
//	Render("")        / Render("/") -> the vectors, one worked example
//	Render("/<a>/<b>")              -> score and explain that pair
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# Jaro-Winkler\n\n")
	b.WriteString("How much of two strings lines up, demoing the ")
	b.WriteString("[`p/moul/x/daily/jarowinkler`](/p/moul/x/daily/jarowinkler/v0) library. ")
	b.WriteString("Scores are integers out of ")
	b.WriteString(strconv.Itoa(jarowinkler.Scale))
	b.WriteString(", so no float ever reaches the chain.\n\n")

	a, c, ok := parseArgs(path)
	if ok {
		b.WriteString("## " + md.InlineCode(a) + " vs " + md.InlineCode(c) + "\n\n")
		b.WriteString(scoreTable(a, c))
		b.WriteString("\n")
		b.WriteString(workingFor(a, c))
		b.WriteString("\n[← back](/r/moul/x/daily/jarowinklerdemo/v0)\n")
		return b.String()
	}

	b.WriteString("## Vectors\n\n")
	vt := ui.NewTable("a", "b", "Jaro", "Jaro-Winkler", "why this pair")
	for _, v := range vectors {
		vt.Row(
			md.InlineCode(v[0]),
			md.InlineCode(v[1]),
			jarowinkler.Percent(jarowinkler.Jaro(v[0], v[1])),
			jarowinkler.Percent(jarowinkler.Winkler(v[0], v[1])),
			v[2],
		)
	}
	b.WriteString(vt.String())
	b.WriteString("\nJaro-Winkler only ever raises a Jaro score, and only once that ")
	b.WriteString("score has reached 0.7. `CRATE`/`TRACE` share no leading rune and ")
	b.WriteString("sits under the threshold anyway, so the two columns agree.\n\n")

	b.WriteString("## Inside one score\n\n")
	b.WriteString(md.InlineCode(explained[0]) + " against " + md.InlineCode(explained[1]) + ":\n\n")
	b.WriteString(workingFor(explained[0], explained[1]))

	b.WriteString("\nAppend two words to score your own pair: ")
	b.WriteString("[`/martha/marhta`](/r/moul/x/daily/jarowinklerdemo/v0:martha/marhta)\n\n")
	b.WriteString("> ℹ️ **Built for names, not for sentences.** The matching window is ")
	b.WriteString("half the longer string, so Jaro-Winkler compares short identifiers ")
	b.WriteString("well and whole paragraphs badly. It is also not an edit distance: ")
	b.WriteString("for \"how many keystrokes apart are these\", reach for ")
	b.WriteString("[`levenshtein`](/r/moul/x/daily/levenshteindemo/v1).\n")
	return b.String()
}

// scoreTable is the two numbers, as percentages and as raw parts per million.
func scoreTable(a, b string) string {
	s := jarowinkler.Explain(a, b)
	t := ui.NewTable("metric", "score", "out of "+strconv.Itoa(jarowinkler.Scale))
	t.Row("Jaro", jarowinkler.Percent(s.Jaro()), strconv.Itoa(s.Jaro()))
	t.Row("Jaro-Winkler", jarowinkler.Percent(s.Winkler()), strconv.Itoa(s.Winkler()))
	return t.String()
}

// workingFor renders what Explain found: the counts the formula is built from,
// and the rune pairing those counts came out of.
func workingFor(a, b string) string {
	s := jarowinkler.Explain(a, b)

	var out strings.Builder
	wt := ui.NewTable("", "value", "")
	// ui.Cell, not md.InlineCode: a and b can be caller text, and a code
	// span does not stop a "|" from opening a column.
	wt.Row("runes in a", strconv.Itoa(s.LenA), ui.Cell(a))
	wt.Row("runes in b", strconv.Itoa(s.LenB), ui.Cell(b))
	wt.Row("window", strconv.Itoa(s.Window), "how far apart two runes may still match")
	wt.Row("matches", strconv.Itoa(s.Matches), "runes with a partner inside the window")
	wt.Row("transpositions", strconv.Itoa(s.Transpositions), "matched pairs that arrived in the wrong order")
	wt.Row("common prefix", strconv.Itoa(s.Prefix), "leading runes, of which Winkler counts four")
	out.WriteString(wt.String())

	pairs := pairUp(a, b, s)
	if len(pairs) == 0 {
		out.WriteString("\nNothing matched, so the score is 0.\n")
		return out.String()
	}

	out.WriteString("\n")
	pt := ui.NewTable("#", "a", "b", "")
	for i, p := range pairs {
		note := ""
		if p.swapped {
			note = "out of order"
		}
		pt.Row(strconv.Itoa(i+1), ui.Cell(p.a), ui.Cell(p.b), note)
	}
	out.WriteString(pt.String())

	if left := unmatched(a, s.MatchedA); left != "" {
		out.WriteString("\nUnmatched in a: " + left + "\n")
	}
	if left := unmatched(b, s.MatchedB); left != "" {
		out.WriteString("\nUnmatched in b: " + left + "\n")
	}
	return out.String()
}

// pair is one matched rune of a lined up with its partner in b.
type pair struct {
	a, b    string
	swapped bool
}

// pairUp walks the two match flags in step, which is exactly how the library
// counts transpositions: every position where the two sequences disagree is
// half of one swap.
func pairUp(a, b string, s jarowinkler.Stats) []pair {
	ra := []rune(a)
	rb := []rune(b)
	pairs := []pair{}
	k := 0
	for i := 0; i < len(ra); i++ {
		if !s.MatchedA[i] {
			continue
		}
		for k < len(rb) && !s.MatchedB[k] {
			k++
		}
		if k >= len(rb) {
			break
		}
		pairs = append(pairs, pair{a: string(ra[i]), b: string(rb[k]), swapped: ra[i] != rb[k]})
		k++
	}
	return pairs
}

// unmatched lists the runes that found no partner. This is prose, not a
// table, so ui.Inline is the right escaper.
func unmatched(s string, flags []bool) string {
	parts := []string{}
	for i, r := range []rune(s) {
		if i < len(flags) && !flags[i] {
			parts = append(parts, ui.Inline(string(r)))
		}
	}
	return strings.Join(parts, ", ")
}

// parseArgs reads "/<a>/<b>" and reports whether both halves are there.
func parseArgs(path string) (string, string, bool) {
	p := strings.TrimPrefix(strings.TrimSpace(path), "/")
	if p == "" {
		return "", "", false
	}
	parts := strings.SplitN(p, "/", 2)
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		return "", "", false
	}
	return parts[0], parts[1], true
}
