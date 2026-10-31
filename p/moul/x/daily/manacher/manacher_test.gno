package manacher

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestRadiiBanana(t *testing.T) {
	// 2n+1 centres: even ones sit between bytes, odd ones on a byte.
	want := []int{0, 1, 0, 1, 0, 3, 0, 5, 0, 3, 0, 1, 0}
	got := Radii("banana")
	uassert.Equal(t, len(want), len(got), "one radius per centre")
	for i := range want {
		uassert.Equal(t, want[i], got[i], "radius at centre "+itoa(i))
	}
}

func TestRadiiEdges(t *testing.T) {
	uassert.Equal(t, 1, len(Radii("")), "the empty string still has one centre")
	uassert.Equal(t, 0, Radii("")[0])

	one := Radii("a")
	uassert.Equal(t, 3, len(one))
	uassert.Equal(t, 0, one[0])
	uassert.Equal(t, 1, one[1])
	uassert.Equal(t, 0, one[2])

	uassert.True(t, Radii(strings.Repeat("x", MaxInput+1)) == nil, "oversized input refused")
	uassert.False(t, Radii(strings.Repeat("x", MaxInput)) == nil, "exactly MaxInput is allowed")
}

// TestRadiiLocatesItsOwnSpan pins the arithmetic the whole package rests on:
// the palindrome at centre i is s[(i-r)/2 : (i+r)/2], and it is a palindrome.
func TestRadiiLocatesItsOwnSpan(t *testing.T) {
	for _, s := range []string{"banana", "babad", "aaaa", "abcde", "forgeeksskeegfor"} {
		for i, r := range Radii(s) {
			start := (i - r) / 2
			sub := s[start : start+r]
			uassert.True(t, IsPalindrome(sub), "centre span of "+s+" at "+itoa(i)+" is a palindrome: "+sub)
		}
	}
}

func TestLongest(t *testing.T) {
	cases := []struct {
		in     string
		start  int
		length int
	}{
		{"banana", 1, 5},
		{"babad", 0, 3},
		{"cbbd", 1, 2},
		{"forgeeksskeegfor", 3, 10},
		{"abcde", 0, 1},
		{"a", 0, 1},
		{"", 0, 0},
		{"aaaa", 0, 4},
	}
	for _, c := range cases {
		start, length := Longest(c.in)
		uassert.Equal(t, c.start, start, "Longest start for "+c.in)
		uassert.Equal(t, c.length, length, "Longest length for "+c.in)
	}
}

// TestLongestIsLeftmost: "babad" holds two length-3 palindromes and the
// leftmost wins, so the answer does not depend on the scan order.
func TestLongestIsLeftmost(t *testing.T) {
	uassert.Equal(t, "bab", LongestString("babad"))
	uassert.Equal(t, "xyzzyx", LongestString("xyzzyxabccba"), "two of equal length, the leftmost wins")
	uassert.Equal(t, "", LongestString(""))
}

func TestCount(t *testing.T) {
	cases := []struct {
		in   string
		want int
	}{
		{"", 0},
		{"a", 1},
		{"ab", 2},
		{"aaa", 6},
		{"abc", 3},
		{"banana", 10},
		{"aaaa", 10},
	}
	for _, c := range cases {
		uassert.Equal(t, c.want, Count(c.in), "Count("+c.in+")")
	}
}

// TestCountMatchesBruteForce is the independent check: a quadratic scan over
// every substring has to agree with the linear one.
func TestCountMatchesBruteForce(t *testing.T) {
	for _, s := range []string{"", "a", "ab", "aba", "abba", "banana", "mississippi", "aaaaa"} {
		brute := 0
		for i := 0; i <= len(s); i++ {
			for j := i + 1; j <= len(s); j++ {
				if IsPalindrome(s[i:j]) {
					brute++
				}
			}
		}
		uassert.Equal(t, brute, Count(s), "Count disagrees with brute force on "+s)
	}
}

func TestSpans(t *testing.T) {
	got := Spans("banana", 3)
	uassert.Equal(t, 3, len(got), "three maximal palindromes of length 3 or more")
	uassert.Equal(t, 1, got[0].Start)
	uassert.Equal(t, 3, got[0].Length)
	uassert.Equal(t, 1, got[1].Start)
	uassert.Equal(t, 5, got[1].Length)
	uassert.Equal(t, 3, got[2].Start)
	uassert.Equal(t, 3, got[2].Length)
}

func TestSpansMinLength(t *testing.T) {
	uassert.Equal(t, 0, len(Spans("abc", 2)), "no palindrome reaches length 2")
	uassert.Equal(t, 3, len(Spans("abc", 1)), "every byte is one")
	uassert.Equal(t, 3, len(Spans("abc", 0)), "a floor below 1 still skips the empty centres")
	uassert.Equal(t, 0, len(Spans("", 1)))
}

// TestSpansAreUniqueAndMaximal: one span per centre, and each is the longest
// palindrome at that centre, so no span is contained in another at the same
// centre.
func TestSpansAreUniqueAndMaximal(t *testing.T) {
	seen := map[int]bool{}
	for _, sp := range Spans("mississippi", 1) {
		centre := 2*sp.Start + sp.Length
		uassert.False(t, seen[centre], "one span per centre")
		seen[centre] = true
		uassert.True(t, IsPalindrome("mississippi"[sp.Start:sp.Start+sp.Length]), "span is a palindrome")
	}
}

func TestIsPalindrome(t *testing.T) {
	for _, s := range []string{"", "a", "aa", "aba", "abba", "racecar"} {
		uassert.True(t, IsPalindrome(s), s+" is a palindrome")
	}
	for _, s := range []string{"ab", "abc", "abca"} {
		uassert.False(t, IsPalindrome(s), s+" is not a palindrome")
	}
}

// TestBytesNotRunes documents the unit. A multi-byte rune reversed is a
// different byte sequence, so "ete" with accents is not a byte palindrome even
// though it reads as one.
func TestBytesNotRunes(t *testing.T) {
	const accented = "été"
	uassert.Equal(t, 5, len(accented), "two-byte runes at both ends")
	uassert.False(t, IsPalindrome(accented), "byte semantics, not rune semantics")
	_, length := Longest(accented)
	uassert.Equal(t, 1, length, "the longest byte palindrome is a single byte")
}

// TestSeparatorIsNotSpecial: the interleaved form uses a separator byte, and a
// caller string full of that same byte must still come out right. Centres and
// separators sit at opposite parities, so they are never compared.
func TestSeparatorIsNotSpecial(t *testing.T) {
	uassert.Equal(t, "#####", LongestString("#####"))
	uassert.Equal(t, "#a#", LongestString("b#a#c"))
	uassert.Equal(t, 3, Count("##"), "both bytes and the pair")
}

// TestLinearOnAdversarialInput is the reason to use Manacher: a run of one byte
// is the worst case for the expand-around-centre scan and costs it O(n^2).
func TestLinearOnAdversarialInput(t *testing.T) {
	s := strings.Repeat("a", 2000)
	start, length := Longest(s)
	uassert.Equal(t, 0, start)
	uassert.Equal(t, 2000, length)
	uassert.Equal(t, 2000*2001/2, Count(s), "every substring of a constant run is a palindrome")
}

func TestOversizedInputIsRefused(t *testing.T) {
	big := strings.Repeat("a", MaxInput+1)
	start, length := Longest(big)
	uassert.Equal(t, 0, start)
	uassert.Equal(t, 0, length, "refused rather than truncated")
	uassert.Equal(t, 0, Count(big))
	uassert.Equal(t, 0, len(Spans(big, 1)))
	uassert.Equal(t, "", LongestString(big))
}

func itoa(i int) string {
	if i == 0 {
		return "0"
	}
	s := ""
	for i > 0 {
		s = string(rune('0'+i%10)) + s
		i /= 10
	}
	return s
}
