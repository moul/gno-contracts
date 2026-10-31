// Package manacher implements Manacher's algorithm: every palindromic
// substring of a string, found in one linear pass.
//
// Expanding around every centre is the obvious way to do this and it is
// quadratic: a run of one byte re-walks the whole string from each position,
// so "aaaa...a" is the input that kills it. Manacher keeps the rightmost
// palindrome found so far and reads the radius of each new centre off its
// mirror inside that window, so no byte is ever compared twice. O(n) time,
// O(n) space, with no bad case. On chain that distinction is the whole point:
// a quadratic scan over caller-supplied text is an attack, not bad luck.
//
// The awkward part of any palindrome routine is that odd and even lengths are
// different problems ("aba" has a middle byte, "abba" does not). This package
// takes the standard fix of interleaving a separator, which gives every
// palindrome an odd length and therefore one integer centre, and then reports
// everything back in the caller's own byte offsets so the transform never
// leaks out.
//
// Operates on BYTES, not runes: gno strings are UTF-8, so a reversed
// multi-byte rune is a different byte sequence and "été" is not a byte
// palindrome even though it reads as one. Byte offsets are the right unit for
// slicing, and they are what [Radii] and [Span] speak.
//
// A live demo of this package is at
// [r/moul/x/daily/manacherdemo](/r/moul/x/daily/manacherdemo/v0).
package manacher

// MaxInput bounds the input so gas stays predictable. A Radii call allocates
// 2n+1 bytes for the interleaved form plus 2n+1 ints for the result, and
// Spans allocates one Span per non-empty centre on top of that, so the worst
// case is about 2n+1 of them. [IsPalindrome] is deliberately NOT bounded: it
// is a two-pointer scan that allocates nothing, so there is no cost for the
// limit to protect, and refusing a long string there would only make the
// cheapest function in the package the fussiest.
const MaxInput = 4096

// sep is the interleaved separator. It needs no special value and does not
// have to be absent from the input: in the interleaved form the separators sit
// at even indices and the original bytes at odd ones, and the two positions
// Radii ever compares, i-k-1 and i+k+1, sum to 2i and therefore always share a
// parity. A separator is only ever compared against another separator. That is
// what makes a string of nothing but '#' come out right.
const sep = '#'

// Span is one palindromic substring of the input, as a byte offset and a byte
// length: the substring is s[Start : Start+Length].
type Span struct {
	Start  int
	Length int
}

// Radii returns one entry per palindrome centre of s, 2*len(s)+1 of them.
// Entry i is the LENGTH in bytes of the longest palindrome centred there, so
// the palindrome itself is s[(i-r)/2 : (i+r)/2].
//
// Even i is a centre between two bytes (an even-length palindrome, possibly
// empty), odd i is a centre on a byte (an odd-length one, never empty). The
// centre of a span is recoverable as 2*Start+Length, which is why no two
// entries can describe the same substring.
//
// Returns nil when s is longer than MaxInput.
func Radii(s string) []int {
	n := len(s)
	if n > MaxInput {
		return nil
	}

	// t is s with a separator before, between and after every byte, so every
	// palindrome of s is an odd-length palindrome of t around a single index.
	t := make([]byte, 2*n+1)
	for i := range t {
		t[i] = sep
	}
	for i := 0; i < n; i++ {
		t[2*i+1] = s[i]
	}

	r := make([]int, len(t))
	// centre and right bound the rightmost palindrome found so far: the window
	// whose mirror lets a new centre start from an answer instead of from zero.
	centre, right := 0, 0
	for i := 0; i < len(t); i++ {
		if i < right {
			// The mirror of i inside the current window has already been
			// measured. Its radius transfers, but only as far as the window
			// reaches: past that edge nothing has been compared yet.
			mirror := 2*centre - i
			r[i] = min(right-i, r[mirror])
		}
		for i-r[i]-1 >= 0 && i+r[i]+1 < len(t) && t[i-r[i]-1] == t[i+r[i]+1] {
			r[i]++
		}
		if i+r[i] > right {
			centre, right = i, i+r[i]
		}
	}
	return r
}

// Longest returns the byte offset and length of the longest palindromic
// substring of s, leftmost when several tie. Length 0 means there was nothing
// to find: s was empty, or longer than MaxInput.
func Longest(s string) (int, int) {
	best, bestLen := 0, 0
	for i, r := range Radii(s) {
		if r > bestLen {
			best, bestLen = (i-r)/2, r
		}
	}
	return best, bestLen
}

// LongestString returns the longest palindromic substring of s, leftmost when
// several tie, or "" when there is none.
func LongestString(s string) string {
	start, length := Longest(s)
	return s[start : start+length]
}

// Count returns how many palindromic substrings s contains, counted by
// position: "aaa" is 6, not 3, because the three single bytes and the two
// pairs are distinct substrings that happen to read alike.
//
// Returns 0 when s is longer than MaxInput.
func Count(s string) int {
	total := 0
	for _, r := range Radii(s) {
		// A centre with radius r contains one palindrome of each length that
		// shares its parity, from r down to 1 or 2, which is (r+1)/2 of them.
		total += (r + 1) / 2
	}
	return total
}

// Spans returns the longest palindrome at every centre whose length is at
// least minLength, left to right by centre. Empty centres are always skipped,
// so a minLength below 1 behaves as 1.
//
// One span per centre is what makes the result small: the shorter palindromes
// nested inside each one are implied by its length and parity, and Count is
// the cheap way to ask how many that is.
//
// Returns nil when s is longer than MaxInput.
func Spans(s string, minLength int) []Span {
	var out []Span
	for i, r := range Radii(s) {
		if r == 0 || r < minLength {
			continue
		}
		out = append(out, Span{Start: (i - r) / 2, Length: r})
	}
	return out
}

// IsPalindrome reports whether s reads the same backwards, byte for byte. The
// empty string and every single byte are palindromes.
//
// Unlike the rest of the package it is not bounded by [MaxInput], because it
// allocates nothing: it compares at most len(s)/2 pairs and stops at the first
// mismatch.
func IsPalindrome(s string) bool {
	for i, j := 0, len(s)-1; i < j; i, j = i+1, j-1 {
		if s[i] != s[j] {
			return false
		}
	}
	return true
}

// min is spelled out rather than imported: gno's builtin set is not Go's, and
// one comparison is not worth a dependency.
func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}
