package kmp

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestTable(t *testing.T) {
	cases := []struct {
		pattern string
		want    []int
	}{
		{"abcabca", []int{0, 0, 0, 1, 2, 3, 4}},
		{"aaaa", []int{0, 1, 2, 3}},
		{"abcd", []int{0, 0, 0, 0}},
		{"ababaa", []int{0, 0, 1, 2, 3, 1}},
		{"a", []int{0}},
	}
	for _, c := range cases {
		got := Table(c.pattern)
		uassert.Equal(t, len(c.want), len(got), "table length for "+c.pattern)
		for i := range c.want {
			uassert.Equal(t, c.want[i], got[i], "table["+itoa(i)+"] for "+c.pattern)
		}
	}
}

func TestTableRejects(t *testing.T) {
	uassert.True(t, Table("") == nil, "empty pattern has no table")
	uassert.True(t, Table(strings.Repeat("x", MaxPattern+1)) == nil, "oversized pattern refused")
	uassert.False(t, Table(strings.Repeat("x", MaxPattern)) == nil, "exactly MaxPattern is allowed")
}

// TestIndexMatchesStdlib pins KMP against strings.Index across a spread of
// inputs — same contract, different algorithm.
func TestIndexMatchesStdlib(t *testing.T) {
	texts := []string{"", "a", "hello world", "aaaaaaab", "abcabcabd", "mississippi"}
	pats := []string{"", "a", "b", "ab", "abd", "issi", "world", "zzz", "mississippi"}
	for _, text := range texts {
		for _, p := range pats {
			uassert.Equal(t, strings.Index(text, p), Index(text, p),
				"Index("+text+","+p+") should match strings.Index")
		}
	}
}

func TestContains(t *testing.T) {
	uassert.True(t, Contains("hello world", "lo w"))
	uassert.False(t, Contains("hello world", "lo  w"))
	uassert.True(t, Contains("anything", ""), "empty pattern is always contained")
}

// TestFindAllOverlapping is the documented divergence from a naive scan.
func TestFindAllOverlapping(t *testing.T) {
	got := FindAll("aaaa", "aa")
	uassert.Equal(t, 3, len(got), "overlapping matches are all reported")
	uassert.Equal(t, 0, got[0])
	uassert.Equal(t, 1, got[1])
	uassert.Equal(t, 2, got[2])
}

func TestFindAllDisjoint(t *testing.T) {
	got := FindAll("abcabcabc", "abc")
	uassert.Equal(t, 3, len(got))
	uassert.Equal(t, 0, got[0])
	uassert.Equal(t, 3, got[1])
	uassert.Equal(t, 6, got[2])
}

func TestFindAllAbsent(t *testing.T) {
	uassert.Equal(t, 0, len(FindAll("abc", "xyz")))
	uassert.Equal(t, 0, len(FindAll("ab", "abcdef")), "pattern longer than text")
}

func TestCount(t *testing.T) {
	uassert.Equal(t, 4, Count("aaaaa", "aa"))
	uassert.Equal(t, 2, Count("mississippi", "issi"))
	uassert.Equal(t, 0, Count("abc", "d"))
}

// TestPathologicalInput is the reason to use KMP: the naive scan is quadratic
// here, KMP is linear. Correctness is what we assert; the cost is the point.
func TestPathologicalInput(t *testing.T) {
	text := strings.Repeat("a", 2000) + "b"
	pattern := strings.Repeat("a", 200) + "b"
	uassert.Equal(t, 1800, Index(text, pattern))
	uassert.Equal(t, 1, Count(text, pattern))
}

// TestBytesNotRunes documents that offsets are byte offsets.
func TestBytesNotRunes(t *testing.T) {
	// "é" is two bytes in UTF-8, so "x" sits at byte 2, not rune 1.
	uassert.Equal(t, 2, Index("éx", "x"))
	uassert.Equal(t, strings.Index("éx", "x"), Index("éx", "x"))
}

func TestMatchAtStartAndEnd(t *testing.T) {
	uassert.Equal(t, 0, Index("abcdef", "abc"))
	uassert.Equal(t, 3, Index("abcdef", "def"))
	uassert.Equal(t, 0, Index("abc", "abc"), "whole-string match")
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
