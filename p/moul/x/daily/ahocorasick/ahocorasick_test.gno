package ahocorasick

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// fmtMatches renders a match slice as "start:end:pattern" joined by spaces, so
// a failing case prints the whole scan instead of the first difference.
func fmtMatches(ms []Match) string {
	parts := make([]string, 0, len(ms))
	for _, m := range ms {
		parts = append(parts, itoa(m.Start)+":"+itoa(m.End)+":"+m.Pattern)
	}
	return strings.Join(parts, " ")
}

func itoa(n int) string {
	if n == 0 {
		return "0"
	}
	var b []byte
	for n > 0 {
		b = append([]byte{byte('0' + n%10)}, b...)
		n /= 10
	}
	return string(b)
}

func TestFindAll(t *testing.T) {
	cases := []struct {
		name     string
		patterns []string
		text     string
		want     string
	}{
		{
			// The textbook automaton from the 1975 paper.
			name:     "ushers",
			patterns: []string{"he", "she", "his", "hers"},
			text:     "ushers",
			want:     "1:4:she 2:4:he 2:6:hers",
		},
		{
			// Every suffix of the longest pattern is also a pattern, so one
			// position must report four matches through the output links.
			name:     "nested suffixes",
			patterns: []string{"abcd", "bcd", "cd", "d"},
			text:     "abcd",
			want:     "0:4:abcd 1:4:bcd 2:4:cd 3:4:d",
		},
		{
			name:     "overlapping",
			patterns: []string{"a", "ab", "bab", "bc", "bca", "c", "caa"},
			text:     "abccab",
			want:     "0:1:a 0:2:ab 1:3:bc 2:3:c 3:4:c 4:5:a 4:6:ab",
		},
		{
			name:     "no match",
			patterns: []string{"xyz", "qq"},
			text:     "the quick brown fox",
			want:     "",
		},
		{
			name:     "empty text",
			patterns: []string{"a"},
			text:     "",
			want:     "",
		},
		{
			// A pattern longer than the text can never match, and must not
			// walk the automaton off its end trying.
			name:     "pattern longer than text",
			patterns: []string{"abcdef"},
			text:     "abc",
			want:     "",
		},
		{
			name:     "repeats",
			patterns: []string{"aa"},
			text:     "aaaa",
			want:     "0:2:aa 1:3:aa 2:4:aa",
		},
		{
			// The empty pattern matches everywhere and nowhere; it is dropped
			// rather than reported at every offset.
			name:     "empty pattern dropped",
			patterns: []string{"", "b"},
			text:     "abc",
			want:     "1:2:b",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := fmtMatches(New(tc.patterns).FindAll(tc.text))
			uassert.Equal(t, tc.want, got)
		})
	}
}

// At one end offset the longest match comes first, because the scan reports
// the node it reached before walking the output links to its shorter
// suffixes. A caller taking the first match per offset gets the greedy one.
func TestFindAllOrdersLongestFirstAtAnEndOffset(t *testing.T) {
	got := New([]string{"he", "she"}).FindAll("she")
	uassert.Equal(t, "0:3:she 1:3:he", fmtMatches(got))
}

// The index is the caller's slot in the pattern slice, not the automaton's
// node number: that is what lets a caller map a match back to whatever it
// stored alongside the pattern.
func TestMatchIndexIsTheCallersSlot(t *testing.T) {
	ms := New([]string{"zz", "he", "qq"}).FindAll("he")
	uassert.Equal(t, 1, len(ms))
	uassert.Equal(t, 1, ms[0].Index)
	uassert.Equal(t, "he", ms[0].Pattern)
}

// A duplicated pattern is two slots, so it reports twice. Deduplicating here
// would silently drop the second caller's payload.
func TestDuplicatePatternsReportOnceperSlot(t *testing.T) {
	ms := New([]string{"ab", "ab"}).FindAll("ab")
	uassert.Equal(t, 2, len(ms))
	uassert.Equal(t, 0, ms[0].Index)
	uassert.Equal(t, 1, ms[1].Index)
}

func TestFindFirst(t *testing.T) {
	m, ok := New([]string{"brown", "fox"}).FindFirst("the quick brown fox")
	uassert.True(t, ok)
	uassert.Equal(t, "brown", m.Pattern)
	uassert.Equal(t, 10, m.Start)

	_, ok = New([]string{"cat"}).FindFirst("the quick brown fox")
	uassert.False(t, ok)
}

// FindFirst stops at the first match, so it must agree with FindAll's head
// rather than with some other traversal order.
func TestFindFirstAgreesWithFindAll(t *testing.T) {
	m := New([]string{"he", "she", "hers"})
	all := m.FindAll("ushers")
	first, ok := m.FindFirst("ushers")
	uassert.True(t, ok)
	uassert.Equal(t, all[0].Start, first.Start)
	uassert.Equal(t, all[0].Pattern, first.Pattern)
}

func TestContains(t *testing.T) {
	m := New([]string{"spam", "eggs"})
	uassert.True(t, m.Contains("green eggs and ham"))
	uassert.False(t, m.Contains("green ham"))
}

// Matching is over BYTES. UTF-8 is self-synchronizing, so a pattern that is
// itself valid UTF-8 can only match on a rune boundary of valid UTF-8 text.
func TestValidUTF8PatternMatchesOnARuneBoundary(t *testing.T) {
	ms := New([]string{"é"}).FindAll("café")
	uassert.Equal(t, "3:5:é", fmtMatches(ms))
}

// The flip side of the same fact, and the reason the doc says bytes: a
// pattern that is a bare continuation byte DOES match inside a rune. A caller
// slicing on that offset splits the rune.
func TestContinuationBytePatternMatchesInsideARune(t *testing.T) {
	ms := New([]string{"\xa9"}).FindAll("café")
	uassert.Equal(t, 1, len(ms))
	uassert.Equal(t, 4, ms[0].Start)
}

// Refusals. The bounds exist so an on-chain caller cannot be handed an
// unbounded build; a refusal is nil, and nil still answers every query.
func TestNewRefusesWhatItCannotBound(t *testing.T) {
	uassert.True(t, New(nil) == nil)
	uassert.True(t, New([]string{}) == nil)
	uassert.True(t, New([]string{"", ""}) == nil)

	tooMany := make([]string, MaxPatterns+1)
	for i := range tooMany {
		tooMany[i] = "p" + itoa(i)
	}
	uassert.True(t, New(tooMany) == nil)

	uassert.True(t, New([]string{strings.Repeat("a", MaxPatternLen+1)}) == nil)
	uassert.True(t, New([]string{strings.Repeat("a", MaxPatternLen)}) != nil)
}

// A nil matcher is what a refused build returns, so every method has to
// survive it: a demo that renders whatever New gave it must not panic.
func TestNilMatcherAnswersEverything(t *testing.T) {
	var m *Matcher
	uassert.Equal(t, 0, len(m.FindAll("anything")))
	uassert.False(t, m.Contains("anything"))
	_, ok := m.FindFirst("anything")
	uassert.False(t, ok)
	uassert.Equal(t, 0, len(m.Patterns()))
	uassert.Equal(t, 0, m.Nodes())
}

// Patterns returns the accepted set, empties dropped, in the caller's order,
// and the returned slice is a copy: mutating it must not corrupt the
// automaton's own view of what it matched.
func TestPatternsIsACopyOfTheAcceptedSet(t *testing.T) {
	m := New([]string{"he", "", "she"})
	got := m.Patterns()
	uassert.Equal(t, "he she", strings.Join(got, " "))
	got[0] = "clobbered"
	uassert.Equal(t, "he she", strings.Join(m.Patterns(), " "))
}

// The automaton is one node per distinct pattern prefix plus the root, which
// is what makes the build linear in the total pattern length rather than in
// the product of the set.
func TestNodesCountsDistinctPrefixesPlusTheRoot(t *testing.T) {
	// he, she, his, hers: prefixes h, he, her, hers, s, sh, she, hi, his = 9.
	uassert.Equal(t, 10, New([]string{"he", "she", "his", "hers"}).Nodes())
	// A single pattern is its own prefix chain.
	uassert.Equal(t, 4, New([]string{"abc"}).Nodes())
}

// The guarantee worth having over a naive scan: the text cursor never moves
// backwards, so a pathological set cannot be made to cost more than one pass.
// 64 patterns that all share a prefix, over a text of the same letter.
func TestPathologicalSetStaysOnePass(t *testing.T) {
	patterns := make([]string, 0, 64)
	for i := 1; i <= 64; i++ {
		patterns = append(patterns, strings.Repeat("a", i))
	}
	ms := New(patterns).FindAll(strings.Repeat("a", 64))
	// Every (start, length) pair with start+length <= 64: 64*65/2.
	uassert.Equal(t, 2080, len(ms))
}

// The merged output lists are what the package doc calls its one departure
// from the paper, so the shape that costs the most is pinned rather than
// asserted in prose. A nested set of k patterns stores 1+2+...+k entries,
// quadratic in k, where a dictionary of distinct words stores one per node.
func TestMergedOutputsAreQuadraticOnANestedSet(t *testing.T) {
	nested := make([]string, 0, 64)
	for i := 1; i <= 64; i++ {
		nested = append(nested, strings.Repeat("a", i))
	}
	uassert.Equal(t, 2080, totalOutputs(New(nested)))

	// Four distinct words, no nesting: one entry per terminal node.
	uassert.Equal(t, 4, totalOutputs(New([]string{"fox", "lazy", "over", "quick"})))

	// he/she/his/hers nests once, "he" inside "she", so one node carries two.
	uassert.Equal(t, 5, totalOutputs(New([]string{"he", "she", "his", "hers"})))
}

func totalOutputs(m *Matcher) int {
	n := 0
	for _, nd := range m.nodes {
		n += len(nd.out)
	}
	return n
}
