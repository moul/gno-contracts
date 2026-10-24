// Package ahocorasickdemo is a small gnoweb demo of the
// [p/moul/x/daily/ahocorasick](/p/moul/x/daily/ahocorasick/v0) library: it runs
// one automaton over a text once and shows the overlapping matches a k-pass
// scan would have to pay k passes for.
//
// It contains no search logic of its own. Stateless, so Render is
// deterministic.
package ahocorasickdemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/x/daily/ahocorasick/v0"
)

// Fixed inputs, never chain state: a demo whose output moves with the block
// height cannot be pinned by an example test.
var (
	textbookPatterns = []string{"he", "she", "his", "hers"}
	textbookText     = "ushers"

	dictPatterns = []string{"the", "he", "fox", "over", "lazy"}
	sentence     = "the quick brown fox jumps over the lazy dog"

	textbook = ahocorasick.New(textbookPatterns)
	dict     = ahocorasick.New(dictPatterns)
)

// Render renders the demo for gnoweb.
//
//	Render("") / Render("/")  -> the textbook automaton and the sentence scan
//	Render("/<text>")         -> scan that text with the same dictionary
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# Aho-Corasick\n\n")
	b.WriteString("One automaton for the whole dictionary, one pass over the text, ")
	b.WriteString("demoing the [`p/moul/x/daily/ahocorasick`](/p/moul/x/daily/ahocorasick/v0) library.\n\n")

	if arg := parseArg(path); arg != "" {
		b.WriteString(renderScan(arg))
		return b.String()
	}

	b.WriteString("## The 1975 example\n\n")
	b.WriteString("Patterns " + list(textbookPatterns) + " over " + md.InlineCode(textbookText) + ". ")
	b.WriteString("Three of the four overlap, and `hers` ends where nothing else starts.\n\n")
	b.WriteString(matchTable(textbook, textbookText))

	b.WriteString("\n## One pass over a sentence\n\n")
	b.WriteString("Patterns " + list(dictPatterns) + " over " + md.InlineCode(sentence) + ".\n\n")
	b.WriteString(matchTable(dict, sentence))

	b.WriteString("\n")
	b.WriteString(stats(dict, sentence))

	b.WriteString("\n> Scan your own text: append it to the path, for instance ")
	b.WriteString("[`/thermos`](/r/moul/x/daily/ahocorasickdemo/v0:/thermos), ")
	b.WriteString("where `the` and `he` overlap on the same three letters.\n")
	return b.String()
}

// renderScan scans the visitor's text with the sentence dictionary.
//
// The argument is the visitor's text and it is shown inside a code span, so it
// goes through md.InlineCode and not ui.Cell: a cell escaper backslashes a
// backtick, and a backslash does not close a backtick inside a span. Only a
// fence wider than anything in the argument does, which is what md.InlineCode
// picks. The table itself only ever holds offsets and dictionary words, never
// a slice of the argument.
func renderScan(arg string) string {
	var b strings.Builder
	b.WriteString("## ")
	b.WriteString(md.InlineCode(arg))
	b.WriteString("\n\nPatterns " + list(dictPatterns) + ".\n\n")

	ms := dict.FindAll(arg)
	if len(ms) == 0 {
		b.WriteString("No pattern occurs in it.\n")
		return b.String()
	}
	b.WriteString(matchTable(dict, arg))
	b.WriteString("\n")
	b.WriteString(stats(dict, arg))
	return b.String()
}

// matchTable renders every match as offsets plus the pattern that matched.
// It never echoes a slice of the scanned text: the pattern is already the
// matched bytes, and it comes from the fixed dictionary rather than from the
// caller.
func matchTable(m *ahocorasick.Matcher, text string) string {
	ms := m.FindAll(text)
	t := ui.NewTable("start", "end", "pattern")
	for _, match := range ms {
		t.Row(
			"`"+strconv.Itoa(match.Start)+"`",
			"`"+strconv.Itoa(match.End)+"`",
			"`"+match.Pattern+"`",
		)
	}
	return t.String()
}

// stats says what the pass actually cost, which is the whole claim: the text
// is read once whatever the dictionary holds.
func stats(m *ahocorasick.Matcher, text string) string {
	return "`" + strconv.Itoa(len(m.Patterns())) + "` patterns, `" +
		strconv.Itoa(m.Nodes()) + "` automaton nodes, `" +
		strconv.Itoa(len(text)) + "` bytes read once, `" +
		strconv.Itoa(len(m.FindAll(text))) + "` matches. " +
		"Running a single-pattern scan per word would read those bytes `" +
		strconv.Itoa(len(m.Patterns())) + "` times instead.\n"
}

// list renders a pattern set as code spans. The patterns are this file's own
// constants, never the caller's.
func list(patterns []string) string {
	parts := make([]string, 0, len(patterns))
	for _, p := range patterns {
		parts = append(parts, "`"+p+"`")
	}
	return strings.Join(parts, ", ")
}

// parseArg takes the one routing slash off and nothing else. It does not cut
// at a later slash and it does not trim: a page that offers to scan what the
// caller typed either scans that string or says it found nothing, and never
// quietly substitutes a shorter or tidier one.
func parseArg(path string) string {
	return strings.TrimPrefix(path, "/")
}
