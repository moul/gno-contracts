package jarowinkler

import (
	"strconv"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestJaroAndWinkler(t *testing.T) {
	cases := []struct {
		name    string
		a, b    string
		jaro    int
		winkler int
	}{
		{"martha", "MARTHA", "MARHTA", 944444, 961111},
		{"dixon", "DIXON", "DICKSONX", 766667, 813333},
		{"dwayne", "DWAYNE", "DUANE", 822222, 840000},
		{"pennsylvania", "PENNSYLVANIA", "PENNCISYLVNIA", 830031, 898019},
		{"no prefix to boost", "JELLYFISH", "SMELLYFISH", 896296, 896296},
		{"below the boost threshold", "CRATE", "TRACE", 733333, 733333},
		{"prefix boosts above it", "TRATE", "TRACE", 866667, 906667},
		{"transpositions only", "arnab", "raanb", 866667, 866667},
		{"identical", "abc", "abc", Scale, Scale},
		{"disjoint", "abc", "xyz", 0, 0},
		{"both empty", "", "", Scale, Scale},
		{"one empty", "a", "", 0, 0},
		{"prefix of the other", "gno", "gnoland", 809524, 866667},
		{"multi-byte runes", "ÉCLAIR", "ÉCLAIRE", 952381, 971429},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			uassert.Equal(t, tc.jaro, Jaro(tc.a, tc.b), "Jaro")
			uassert.Equal(t, tc.winkler, Winkler(tc.a, tc.b), "Winkler")
		})
	}
}

// TestSymmetric pins that neither score depends on argument order, which the
// window and the transposition walk make non-obvious.
func TestSymmetric(t *testing.T) {
	pairs := [][2]string{
		{"DIXON", "DICKSONX"},
		{"DWAYNE", "DUANE"},
		{"gno", "gnoland"},
		{"PENNSYLVANIA", "PENNCISYLVNIA"},
	}
	for _, p := range pairs {
		uassert.Equal(t, Jaro(p[0], p[1]), Jaro(p[1], p[0]), "Jaro "+p[0]+"/"+p[1])
		uassert.Equal(t, Winkler(p[0], p[1]), Winkler(p[1], p[0]), "Winkler "+p[0]+"/"+p[1])
	}
}

func TestExplain(t *testing.T) {
	s := Explain("MARTHA", "MARHTA")
	uassert.Equal(t, 6, s.LenA)
	uassert.Equal(t, 6, s.LenB)
	uassert.Equal(t, 2, s.Window)
	uassert.Equal(t, 6, s.Matches)
	uassert.Equal(t, 1, s.Transpositions)
	uassert.Equal(t, 3, s.Prefix)
	uassert.Equal(t, 6, len(s.MatchedA))
	uassert.Equal(t, 6, len(s.MatchedB))
	for i, m := range s.MatchedA {
		uassert.True(t, m, "MatchedA["+strconv.Itoa(i)+"]")
	}
}

// TestExplainCountsRunesNotBytes is the reason Explain reports lengths at all:
// a byte-wise port would report 7 and 8 here and pick a wider window.
func TestExplainCountsRunesNotBytes(t *testing.T) {
	s := Explain("ÉCLAIR", "ÉCLAIRE")
	uassert.Equal(t, 6, s.LenA)
	uassert.Equal(t, 7, s.LenB)
	uassert.Equal(t, 6, s.Prefix)
	uassert.Equal(t, 6, s.Matches)
}

// TestExplainUnmatchedRunes pins the flags a caller renders an alignment from.
func TestExplainUnmatchedRunes(t *testing.T) {
	s := Explain("DIXON", "DICKSONX")
	uassert.Equal(t, 4, s.Matches)
	uassert.Equal(t, 0, s.Transpositions)
	// "X" of DIXON matches nothing: D, I, O, N do.
	want := []bool{true, true, false, true, true}
	uassert.Equal(t, len(want), len(s.MatchedA))
	for i, w := range want {
		uassert.Equal(t, w, s.MatchedA[i], "MatchedA["+strconv.Itoa(i)+"]")
	}
}

// TestWinklerTunedKnobs walks the two parameters the fixed Winkler hides: a
// threshold of 0 boosts a pair Winkler leaves alone, and a prefix size of 0
// turns the boost off entirely.
func TestWinklerTunedKnobs(t *testing.T) {
	uassert.Equal(t, 733333, Winkler("CRATE", "TRACE"), "unboosted below the threshold")
	uassert.Equal(t, 733333, WinklerTuned("CRATE", "TRACE", 0, 4), "no prefix to boost with")
	uassert.Equal(t, 866667, WinklerTuned("TRATE", "TRACE", 0, 0), "prefix size 0 disables the boost")
	uassert.Equal(t, 893333, WinklerTuned("TRATE", "TRACE", 0, 2), "a shorter prefix boosts less")
	uassert.Equal(t, 961111, WinklerTuned("MARTHA", "MARHTA", 700000, 4), "the documented defaults")
	uassert.Equal(t, 944444, WinklerTuned("MARTHA", "MARHTA", 950000, 4), "a threshold above the score")
}

// TestWinklerNegativePrefixSize pins that a negative cap behaves like 0: the
// boost may only raise a score, so it must never come back below plain Jaro.
func TestWinklerNegativePrefixSize(t *testing.T) {
	jaro := Jaro("TRATE", "TRACE")
	uassert.Equal(t, 866667, jaro)
	for _, size := range []int{-1, -4, -1000} {
		uassert.Equal(t, jaro, WinklerTuned("TRATE", "TRACE", 0, size), "prefix size "+strconv.Itoa(size))
	}
}

// TestLongInputDoesNotOverflow pins the case Scale*num used to overflow in 64
// bits: two identical 7,000-rune strings, whose Jaro fraction is 3n^3/3n^3.
// The stats are built directly because walking 7,000 runes in a test costs
// far more than the arithmetic being checked.
func TestLongInputDoesNotOverflow(t *testing.T) {
	for _, n := range []int64{7000, 100000, 600000} {
		s := Stats{LenA: int(n), LenB: int(n), Matches: int(n), Prefix: int(n), num: 3 * n * n * n, den: 3 * n * n * n}
		uassert.Equal(t, Scale, s.Jaro(), "jaro at "+strconv.Itoa(int(n)))
		uassert.Equal(t, Scale, s.Winkler(), "winkler at "+strconv.Itoa(int(n)))
	}
	// One unmatched rune in 7,000: the boost must still land strictly between
	// the Jaro score and a perfect match.
	n := int64(7000)
	m := n - 1
	s := Stats{LenA: int(n), LenB: int(n), Matches: int(m), Prefix: 4, num: m*m*n + m*m*n + m*n*n, den: 3 * n * n * m}
	j, w := s.Jaro(), s.Winkler()
	uassert.True(t, j < w && w < Scale, "jaro "+strconv.Itoa(j)+" winkler "+strconv.Itoa(w))
}

func TestPercent(t *testing.T) {
	cases := []struct {
		score int
		want  string
	}{
		{Scale, "100.00%"},
		{944444, "94.44%"},
		{961111, "96.11%"},
		{809524, "80.95%"},
		{0, "0.00%"},
		{5000, "0.50%"},
		{500, "0.05%"},
		{100000, "10.00%"},
	}
	for _, tc := range cases {
		uassert.Equal(t, tc.want, Percent(tc.score), "Percent")
	}
}
