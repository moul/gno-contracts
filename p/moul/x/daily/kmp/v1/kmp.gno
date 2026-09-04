// Package kmp implements Knuth–Morris–Pratt substring search as a pure,
// reusable package.
//
// The naive scan re-compares characters it has already matched, so a hostile
// input like "aaaaaaab" in "aaaaaaaaaaaaaaab" costs O(n*m). KMP precomputes a
// failure table — for every prefix, the length of the longest proper prefix
// that is also a suffix — and uses it to slide the pattern without ever moving
// the text cursor backwards. That makes the scan O(n+m) with O(m) extra memory,
// and it never degrades: worst case equals best case, which is what makes it
// safe to run on chain where a pathological input is an attack, not bad luck.
//
// Operates on BYTES, not runes: gno strings are UTF-8, so a match index is a
// byte offset. That is the right unit for slicing and it keeps the failure
// table cheap; callers doing rune arithmetic must convert.
//
// A live demo of this package is at
// [r/moul/x/daily/kmpdemo](/r/moul/x/daily/kmpdemo/v1).
package kmp

// MaxPattern bounds the failure table so gas stays predictable.
const MaxPattern = 1024

// Table returns the KMP failure table for pattern: table[i] is the length of
// the longest proper prefix of pattern[:i+1] that is also a suffix of it.
// Returns nil when the pattern is empty or longer than MaxPattern.
func Table(pattern string) []int {
	m := len(pattern)
	if m == 0 || m > MaxPattern {
		return nil
	}
	t := make([]int, m)
	k := 0
	for i := 1; i < m; i++ {
		for k > 0 && pattern[i] != pattern[k] {
			k = t[k-1]
		}
		if pattern[i] == pattern[k] {
			k++
		}
		t[i] = k
	}
	return t
}

// Index returns the byte offset of the first occurrence of pattern in text, or
// -1 if absent. An empty pattern matches at 0, matching strings.Index.
func Index(text, pattern string) int {
	all := findAll(text, pattern, 1)
	if len(all) == 0 {
		return -1
	}
	return all[0]
}

// Contains reports whether pattern occurs in text.
func Contains(text, pattern string) bool { return Index(text, pattern) >= 0 }

// FindAll returns the byte offsets of every match, including OVERLAPPING ones:
// FindAll("aaaa", "aa") is [0 1 2], not [0 2]. Overlap is the honest reading of
// "every occurrence" and the caller can always filter.
func FindAll(text, pattern string) []int { return findAll(text, pattern, 0) }

// Count returns how many times pattern occurs, counting overlaps.
func Count(text, pattern string) int { return len(FindAll(text, pattern)) }

// findAll collects match offsets, stopping after limit matches (0 = no limit).
func findAll(text, pattern string, limit int) []int {
	m := len(pattern)
	if m == 0 {
		return []int{0}
	}
	if m > len(text) || m > MaxPattern {
		return nil
	}
	t := Table(pattern)
	if t == nil {
		return nil
	}

	var out []int
	k := 0
	for i := 0; i < len(text); i++ {
		for k > 0 && text[i] != pattern[k] {
			k = t[k-1]
		}
		if text[i] == pattern[k] {
			k++
		}
		if k == m {
			out = append(out, i-m+1)
			if limit > 0 && len(out) >= limit {
				return out
			}
			k = t[k-1] // allow overlapping matches
		}
	}
	return out
}
