// Package jarowinkler ports the Jaro and Jaro-Winkler string similarity
// metrics (as found in Go libraries like xrash/smetrics) to gno, as a reusable
// pure package.
//
// Where Levenshtein counts the edits between two strings, Jaro measures how
// much of them lines up: how many runes match within a sliding window, and how
// many of those matches arrive out of order. Winkler then rewards a shared
// prefix, which is what makes the pair the classic choice for comparing names
// and short identifiers rather than sentences.
//
// # Integers only
//
// Scores are returned as parts per million, [Scale] being a perfect match, so
// nothing here touches a float. Every score is computed from one exact
// rational, with a single round-half-up at the end: a Jaro-Winkler score is
// never the rounded Jaro score rounded a second time, which is where a naive
// integer port loses its last digit.
//
// The exact arithmetic is done in int64 and holds for inputs up to roughly
// 6,000 runes, well past what the O(n*m) window walk is worth on chain.
//
// A live demo of this package is at
// [r/moul/x/daily/jarowinklerdemo](/r/moul/x/daily/jarowinklerdemo/v0).
package jarowinkler

import "strconv"

// Scale is the value of a perfect match: scores are parts per million, so
// 944444 reads as 0.944444 and [Percent] turns it into "94.44%".
const Scale = 1000000

// defaultBoostThreshold is the Jaro score a pair must reach before [Winkler]
// applies the prefix boost at all. Winkler's own papers use 0.7.
const defaultBoostThreshold = 700000

// defaultPrefixSize is how many leading runes [Winkler] lets the boost count.
const defaultPrefixSize = 4

// Stats is everything [Explain] found while comparing two strings: the inputs
// as rune counts, the matching window it derived from them, and the matches,
// transpositions and common prefix the scores are built out of.
//
// MatchedA and MatchedB flag, per rune, which ones found a partner. They are
// what a caller renders an alignment from, and they are why Explain exists:
// the scores alone never say which rune was the one that did not fit.
type Stats struct {
	LenA, LenB     int
	Window         int
	Matches        int
	Transpositions int
	Prefix         int
	MatchedA       []bool
	MatchedB       []bool

	// num and den hold the Jaro score as an exact fraction, so Winkler can
	// boost the unrounded value. Zero for a pair with no matches.
	num, den int64
}

// Explain compares a and b and returns the full working behind their scores.
//
// Both strings are decoded as runes, so "ÉCLAIR" is six runes and not eight
// bytes: a byte-wise port would compare the halves of a multi-byte rune and
// pick a wider window from the inflated lengths.
func Explain(a, b string) Stats {
	ra := []rune(a)
	rb := []rune(b)

	s := Stats{
		LenA:     len(ra),
		LenB:     len(rb),
		MatchedA: make([]bool, len(ra)),
		MatchedB: make([]bool, len(rb)),
	}
	if len(ra) == 0 || len(rb) == 0 {
		return s
	}

	// Two runes may only match if they sit within half the longer string of
	// each other, minus one. That window is what separates Jaro from a plain
	// "how many runes do these share" count.
	longest := len(ra)
	if len(rb) > longest {
		longest = len(rb)
	}
	s.Window = longest/2 - 1
	if s.Window < 0 {
		s.Window = 0
	}

	for i := 0; i < len(ra); i++ {
		lo := i - s.Window
		if lo < 0 {
			lo = 0
		}
		hi := i + s.Window
		if hi > len(rb)-1 {
			hi = len(rb) - 1
		}
		for j := lo; j <= hi; j++ {
			if s.MatchedB[j] || ra[i] != rb[j] {
				continue
			}
			s.MatchedA[i] = true
			s.MatchedB[j] = true
			s.Matches++
			break
		}
	}
	if s.Matches == 0 {
		return s
	}

	// Walk both match sequences in order. Every position where they disagree
	// is half a transposition: "MARTHA" and "MARHTA" disagree twice, on T and
	// on H, which is the one swap a reader sees.
	k := 0
	halves := 0
	for i := 0; i < len(ra); i++ {
		if !s.MatchedA[i] {
			continue
		}
		for !s.MatchedB[k] {
			k++
		}
		if ra[i] != rb[k] {
			halves++
		}
		k++
	}
	s.Transpositions = halves / 2

	for s.Prefix < len(ra) && s.Prefix < len(rb) && ra[s.Prefix] == rb[s.Prefix] {
		s.Prefix++
	}

	// jaro = (m/|a| + m/|b| + (m-t)/m) / 3, over the common denominator
	// 3*|a|*|b|*m so that the division happens exactly once, at the end.
	m := int64(s.Matches)
	t := int64(s.Transpositions)
	la := int64(s.LenA)
	lb := int64(s.LenB)
	s.num = m*m*lb + m*m*la + (m-t)*la*lb
	s.den = 3 * la * lb * m
	return s
}

// Jaro returns the Jaro similarity of a and b, from 0 to [Scale].
//
// Two empty strings are a perfect match; one empty string matches nothing.
// The result does not depend on the order of the arguments.
func Jaro(a, b string) int {
	return Explain(a, b).Jaro()
}

// Jaro returns the Jaro similarity these stats describe, from 0 to [Scale].
func (s Stats) Jaro() int {
	if s.LenA == 0 && s.LenB == 0 {
		return Scale
	}
	if s.Matches == 0 {
		return 0
	}
	return int(round(Scale*s.num, s.den))
}

// Winkler returns the Jaro-Winkler similarity of a and b, from 0 to [Scale]:
// the Jaro score, raised towards a perfect match by a tenth for each of up to
// four shared leading runes, and only once the Jaro score has reached 0.7.
//
// Those are the constants from Winkler's own papers; [WinklerTuned] takes them
// as arguments.
func Winkler(a, b string) int {
	return WinklerTuned(a, b, defaultBoostThreshold, defaultPrefixSize)
}

// WinklerTuned is [Winkler] with its two constants exposed. boostThreshold is
// the Jaro score below which no boost applies at all, on the same 0 to [Scale]
// range; prefixSize caps how many leading runes may be counted, and 0 turns
// the boost off entirely, leaving plain Jaro.
func WinklerTuned(a, b string, boostThreshold, prefixSize int) int {
	return Explain(a, b).WinklerTuned(boostThreshold, prefixSize)
}

// Winkler returns the Jaro-Winkler similarity these stats describe, using the
// same defaults as the [Winkler] function.
func (s Stats) Winkler() int {
	return s.WinklerTuned(defaultBoostThreshold, defaultPrefixSize)
}

// WinklerTuned returns the Jaro-Winkler similarity these stats describe, with
// the two constants documented on the [WinklerTuned] function.
func (s Stats) WinklerTuned(boostThreshold, prefixSize int) int {
	jaro := s.Jaro()
	if s.Matches == 0 || jaro < boostThreshold {
		return jaro
	}
	l := int64(s.Prefix)
	if limit := int64(prefixSize); l > limit {
		l = limit
	}
	if l == 0 {
		return jaro
	}
	// winkler = jaro + l*(1-jaro)/10, kept over the unrounded jaro = num/den
	// so the score is rounded once rather than built out of a rounded one.
	num := 10*s.num + l*(s.den-s.num)
	den := 10 * s.den
	return int(round(Scale*num, den))
}

// Percent formats a 0 to [Scale] score as a percentage with two decimals, as
// in "94.44%". Digits past the second are dropped, never rounded up, so a
// score is never shown as a perfect match it did not reach.
func Percent(score int) string {
	if score < 0 {
		score = 0
	}
	whole := score / 10000
	cents := (score % 10000) / 100
	out := strconv.Itoa(whole) + "."
	if cents < 10 {
		out += "0"
	}
	return out + strconv.Itoa(cents) + "%"
}

// round divides num by den, rounding halves away from zero. Both are positive
// here: every numerator above is a count of matched runes.
func round(num, den int64) int64 {
	return (num + den/2) / den
}
