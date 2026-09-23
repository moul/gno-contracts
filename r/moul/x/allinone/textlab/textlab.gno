// Package textlab runs every string algorithm in p/moul over one input at
// once, so they can be compared rather than read about one at a time.
//
// Each of these has its own demo realm showing it alone. What none of those can
// show is how the answers differ for the SAME word, which is the only question
// a reader actually has: soundex and levenshtein both claim to tell you whether
// two words are alike, and they are measuring different things.
//
// soundex keys on the FIRST LETTER and then on consonant classes, so it is
// blind to how the rest is spelled. levenshtein counts edits and is blind to
// how it sounds. "knight" and "night" are the clean case: one edit apart (83%
// similar) and yet soundex calls them unrelated, K523 against N230, because
// the silent K changes the first character of the code. "robert" and "rupert"
// go the other way, identical codes at two edits apart. Measured 2026-09-23
// against the packages in this tree, not quoted from a textbook.
//
//	/r/moul/x/allinone/textlab/v0:knight
//	/r/moul/x/allinone/textlab/v0:knight/night   compares two
//
// Eight packages, no state, nothing to redeploy carefully: the input comes out
// of the render path and nothing is stored.
package textlab

import (
	"strconv"
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/realmpath/v0"
	"gno.land/p/moul/x/daily/levenshtein/v0"
	"gno.land/p/moul/x/daily/piglatin/v0"
	"gno.land/p/moul/x/daily/romannum/v0"
	"gno.land/p/moul/x/daily/rot13/v0"
	"gno.land/p/moul/x/daily/soundex/v0"
	"gno.land/r/moul/config/v1"
)

const realmPath = "gno.land/r/moul/x/allinone/textlab/v0"

// maxInput bounds what a render path can carry into the algorithms below.
// levenshtein.Matrix is O(len(a) * len(b)), so an unbounded pair of inputs is
// a way to make a query expensive for whoever serves it.
const maxInput = 64

// defaultWord is what the root view demonstrates, chosen because it is the
// textbook case where the two similarity measures disagree: "knight" and
// "night" sound identical to soundex and are one edit apart.
const defaultWord = "knight"

// Render takes its input from the path: one word, or two separated by "/".
func Render(path string) string {
	req := realmpath.Parse(path)

	a := strings.TrimSpace(req.PathPart(0))
	b := strings.TrimSpace(req.PathPart(1))
	if a == "" {
		a = defaultWord
	}

	var out strings.Builder
	out.WriteString(config.TopBlockFor(realmPath))
	out.WriteString(md.H1("allinone: textlab"))
	out.WriteString("\nEight packages over one input. ")
	out.WriteString(md.Link("source", config.MygnoscanFor(realmPath)))
	out.WriteString("\n\n")

	if tooLong(a) || tooLong(b) {
		out.WriteString(ui.Empty("input too long: max " + strconv.Itoa(maxInput) + " bytes"))
		out.WriteString("\n")
		out.WriteString(config.BottomBlockFor(realmPath))
		return out.String()
	}

	out.WriteString(renderOne(a))
	if b != "" {
		out.WriteString("\n")
		out.WriteString(renderPair(a, b))
	} else {
		out.WriteString("\n")
		out.WriteString(renderTry())
	}

	out.WriteString(config.BottomBlockFor(realmPath))
	return out.String()
}

func tooLong(s string) bool { return len(s) > maxInput }

// renderOne is every single-input algorithm, one row each.
//
// ui.Cell, not ui.Inline: these land in table cells, where an unescaped pipe
// would silently eat a column. The input is whatever someone put in a URL.
func renderOne(word string) string {
	t := ui.NewTable("package", "answer")
	t.Row("`x/daily/soundex`", ui.Cell(soundex.Encode(word)))
	t.Row("`x/daily/rot13`", ui.Cell(rot13.Rot13(word)))
	t.Row("`x/daily/piglatin`", ui.Cell(piglatin.Translate(word)))
	t.Row("`x/daily/romannum`", ui.Cell(romanOf(word)))

	return md.H2("Input: "+ui.Inline(word)) + "\n" + t.String()
}

// romanOf shows the round trip both ways, because romannum is the one package
// here whose input is a number rather than a word.
//
// FromRoman PANICS on anything that is not a roman numeral rather than
// returning zero, and the input here comes out of a URL, so it is screened
// first. Without that screen the DEFAULT view aborts: "knight" is not a roman
// numeral, and neither is most of what anyone would type.
func romanOf(word string) string {
	if n, err := strconv.Atoi(word); err == nil {
		if n <= 0 || n > 3999 {
			return "out of range (1..3999)"
		}
		return romannum.ToRoman(n)
	}
	upper := strings.ToUpper(word)
	if !isRomanNumeral(upper) {
		return "not a number"
	}
	if n := romannum.FromRoman(upper); n > 0 {
		return strconv.Itoa(n) + " (read as roman)"
	}
	return "not a number"
}

// isRomanNumeral reports whether every byte is a roman digit. It is a screen
// for romanOf, not a validity check: "IIII" passes here and FromRoman decides.
func isRomanNumeral(s string) bool {
	if s == "" {
		return false
	}
	for i := 0; i < len(s); i++ {
		switch s[i] {
		case 'I', 'V', 'X', 'L', 'C', 'D', 'M':
		default:
			return false
		}
	}
	return true
}

// renderPair is the comparison, and the reason this realm exists: the two
// similarity measures answer different questions, and a reader should watch
// them disagree rather than be told they might.
func renderPair(a, b string) string {
	sa, sb := soundex.Encode(a), soundex.Encode(b)

	t := ui.NewTable("measure", "answer")
	t.Row("`soundex` of "+ui.Cell(a), ui.Cell(sa))
	t.Row("`soundex` of "+ui.Cell(b), ui.Cell(sb))
	t.Row("sound alike", yesNo(soundex.Match(a, b)))
	t.Row("`levenshtein` distance", strconv.Itoa(levenshtein.Distance(a, b)))
	t.Row("`levenshtein` similarity", strconv.Itoa(levenshtein.Similarity(a, b))+"%")

	return md.H2("Compared with "+ui.Inline(b)) + "\n" + t.String()
}

func yesNo(b bool) string {
	if b {
		return "yes"
	}
	return "no"
}

func renderTry() string {
	return md.H2("Try two") + "\n" +
		md.BulletList([]string{
			md.Link("knight vs night", "/r/moul/x/allinone/textlab/v0:knight/night") +
				" (one edit apart, yet soundex says unrelated)",
			md.Link("robert vs rupert", "/r/moul/x/allinone/textlab/v0:robert/rupert") +
				" (two edits apart, yet soundex says identical)",
			md.Link("1987 as a roman numeral", "/r/moul/x/allinone/textlab/v0:1987"),
		})
}
