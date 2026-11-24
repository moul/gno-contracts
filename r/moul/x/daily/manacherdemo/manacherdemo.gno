// Package manacherdemo is a small gnoweb demo of the linear-time palindrome
// scan provided by the [p/moul/x/daily/manacher](/p/moul/x/daily/manacher/v0)
// library: the interleaving trick that makes odd and even lengths the same
// problem, the radius of every centre of one worked word, the longest
// palindromic substring of a handful of inputs, and the counting identity.
//
// It contains no palindrome logic of its own, and no state. Every string on
// the page is a constant, so Render is identical on every call and on every
// node, which is what lets an example test pin it.
package manacherdemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/x/daily/manacher/v0"
)

// word is the worked example. "banana" is small enough to table in full and
// still carries nested odd-length palindromes, which is where a naive scan
// does its repeated work.
const word = "banana"

// samples are the inputs the longest-substring table answers for.
var samples = []struct {
	in   string
	note string
}{
	{"banana", "nested odd centres"},
	{"babad", "two of length 3, leftmost wins"},
	{"cbbd", "an even centre, between two bytes"},
	{"forgeeksskeegfor", "the answer is not at either end"},
	{"abcde", "nothing but single bytes"},
	{"aaaaaaaa", "the input that kills the naive scan"},
	{"#####", "the separator byte is not reserved"},
	{"", "no centre has anything in it"},
}

// Render renders the demo for gnoweb.
//
//	Render("") / Render("/") -> the full demo
func Render(path string) string {
	var b strings.Builder

	b.WriteString("# Manacher's algorithm\n\n")
	b.WriteString("Every palindromic substring of a string, in one linear pass. ")
	b.WriteString("Demoing the ")
	b.WriteString("[`p/moul/x/daily/manacher`](/p/moul/x/daily/manacher/v0) ")
	b.WriteString("library.\n\n")

	b.WriteString("## Odd and even are one problem\n\n")
	b.WriteString("`aba` has a middle byte and `abba` does not, so a routine ")
	b.WriteString("that expands around centres has two cases to get right and ")
	b.WriteString("two places to get them wrong. Interleaving a separator ")
	b.WriteString("removes the distinction: every palindrome of the original ")
	b.WriteString("becomes an odd-length palindrome of the transform, around ")
	b.WriteString("exactly one index.\n\n")
	b.WriteString("```\n" + word + "\n" + interleaved(word) + "\n```\n\n")
	b.WriteString("The separator needs no reserved value, which is the part ")
	b.WriteString("that looks unsafe and is not. Separators land on even ")
	b.WriteString("indices and the original bytes on odd ones, and the two ")
	b.WriteString("positions the scan compares always sum to twice the centre, ")
	b.WriteString("so they share a parity. A separator is only ever compared ")
	b.WriteString("against another separator, and an input of nothing but ")
	b.WriteString("`#` comes out right.\n\n")

	b.WriteString("## Every centre of `" + word + "`\n\n")
	b.WriteString("One row per centre, " + strconv.Itoa(2*len(word)+1) + " of them. ")
	b.WriteString("The length is what the library returns; the span is ")
	b.WriteString("`s[(i-len)/2 : (i+len)/2]`, which is the only arithmetic a ")
	b.WriteString("caller ever needs.\n\n")
	ct := ui.NewTable("centre", "sits on", "length", "palindrome")
	for i, r := range manacher.Radii(word) {
		on := "between bytes"
		if i%2 == 1 {
			on = "byte `" + word[i/2:i/2+1] + "`"
		}
		span := "_empty_"
		if r > 0 {
			span = "`" + word[(i-r)/2:(i+r)/2] + "`"
		}
		ct.Row(strconv.Itoa(i), on, strconv.Itoa(r), span)
	}
	b.WriteString(ct.String() + "\n")
	b.WriteString("Between-byte centres are 0 everywhere here because ")
	b.WriteString("`" + word + "` has no two adjacent bytes alike. That is the ")
	b.WriteString("even case costing nothing rather than being skipped.\n\n")

	b.WriteString("## The longest palindromic substring\n\n")
	lt := ui.NewTable("input", "longest", "at", "length", "palindromes")
	for _, s := range samples {
		start, length := manacher.Longest(s.in)
		shown := "_none_"
		if length > 0 {
			shown = "`" + s.in[start:start+length] + "`"
		}
		in := "_empty_"
		if s.in != "" {
			in = "`" + s.in + "`"
		}
		lt.Row(in, shown, strconv.Itoa(start), strconv.Itoa(length),
			strconv.Itoa(manacher.Count(s.in)))
	}
	b.WriteString(lt.String() + "\n")
	b.WriteString("Ties go to the leftmost, which is what makes the answer a ")
	b.WriteString("function of the input and not of the scan order. A realm ")
	b.WriteString("whose page depended on which equal-length match the loop ")
	b.WriteString("happened to keep would render differently on two nodes ")
	b.WriteString("running the same code.\n\n")

	b.WriteString("## Counting counts positions\n\n")
	b.WriteString("`Count` asks how many palindromic substrings there are, by ")
	b.WriteString("position: `aaa` is 6, not 3, because the three single bytes ")
	b.WriteString("and the two pairs are distinct substrings that happen to ")
	b.WriteString("read alike. A centre of length `r` holds `(r+1)/2` of them, ")
	b.WriteString("one per length sharing its parity, so the total falls out ")
	b.WriteString("of the same single pass.\n\n")
	b.WriteString("A constant run is the extreme: every substring of ")
	b.WriteString("`aaaaaaaa` is a palindrome, all ")
	b.WriteString(strconv.Itoa(manacher.Count("aaaaaaaa")) + " of them, and ")
	b.WriteString("listing them would cost quadratic output where counting ")
	b.WriteString("them costs none.\n\n")

	b.WriteString("## Maximal spans\n\n")
	b.WriteString("`Spans` returns the longest palindrome at each centre, ")
	b.WriteString("skipping the empty ones. One per centre is what keeps the ")
	b.WriteString("result small: the shorter palindromes nested inside each ")
	b.WriteString("are implied by its length and parity.\n\n")
	st := ui.NewTable("start", "length", "substring")
	for _, sp := range manacher.Spans(word, 3) {
		st.Row(strconv.Itoa(sp.Start), strconv.Itoa(sp.Length),
			"`"+word[sp.Start:sp.Start+sp.Length]+"`")
	}
	b.WriteString(st.OrEmpty("No span reaches the minimum length.") + "\n")

	b.WriteString("## Why it belongs on chain\n\n")
	b.WriteString("Expanding around every centre is quadratic, and the input ")
	b.WriteString("that triggers the worst case is a run of one byte: the ")
	b.WriteString("cheapest string in the world to send. Manacher reads each ")
	b.WriteString("new centre off its mirror inside the rightmost palindrome ")
	b.WriteString("found so far, so no byte is compared twice and the worst ")
	b.WriteString("case equals the best one. A scan over caller-supplied text ")
	b.WriteString("whose cost the caller chooses is an attack, not bad luck.\n\n")
	b.WriteString("Offsets are **byte** offsets. gno strings are UTF-8 and a ")
	b.WriteString("reversed multi-byte rune is a different byte sequence, so ")
	b.WriteString("an accented word that reads as a palindrome is usually not ")
	b.WriteString("one by bytes. Bytes are the right unit for slicing, and a ")
	b.WriteString("caller doing rune arithmetic converts.\n")

	return b.String()
}

// interleaved renders the transform the way the library builds it, for the
// code block above. The library keeps its own copy private: this is the
// picture, not the implementation.
func interleaved(s string) string {
	var b strings.Builder
	b.WriteString("#")
	for i := 0; i < len(s); i++ {
		b.WriteString(s[i:i+1] + "#")
	}
	return b.String()
}
