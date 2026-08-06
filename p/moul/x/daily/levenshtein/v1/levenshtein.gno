// Package levenshtein ports the classic Levenshtein edit-distance algorithm
// (as found in Go libraries like agext/levenshtein) to gno — as a reusable pure
// package.
//
// The core is the textbook dynamic-programming matrix: the minimum number of
// single-character insertions, deletions, or substitutions to turn string a
// into string b. It is fully rune-aware and pure (deterministic), so it runs
// happily on-chain.
//
// A live demo of this package (an interactive distance calculator with the DP
// table) is at [r/moul/x/daily/levenshteindemo](/r/moul/x/daily/levenshteindemo/v1).
package levenshtein

// Distance returns the Levenshtein edit distance between a and b.
//
// It counts single-rune insertions, deletions, and substitutions and works on
// runes (not bytes), so multi-byte UTF-8 input is handled correctly. The
// classic two-row DP is used, so memory is O(min(len)) and time is O(len(a)*len(b)).
func Distance(a, b string) int {
	ra := []rune(a)
	rb := []rune(b)

	// Keep the shorter slice as the inner (column) dimension.
	if len(ra) < len(rb) {
		ra, rb = rb, ra
	}
	n := len(ra)
	m := len(rb)
	if m == 0 {
		return n
	}

	// prev[j] = distance between ra[:i] and rb[:j].
	prev := make([]int, m+1)
	for j := 0; j <= m; j++ {
		prev[j] = j
	}
	curr := make([]int, m+1)

	for i := 1; i <= n; i++ {
		curr[0] = i
		for j := 1; j <= m; j++ {
			cost := 1
			if ra[i-1] == rb[j-1] {
				cost = 0
			}
			curr[j] = min3(
				curr[j-1]+1,    // insertion
				prev[j]+1,      // deletion
				prev[j-1]+cost, // substitution / match
			)
		}
		prev, curr = curr, prev
	}
	return prev[m]
}

// Matrix returns the full (len(a)+1) x (len(b)+1) DP matrix used by Distance.
// matrix[i][j] is the edit distance between the first i runes of a and the
// first j runes of b. The bottom-right cell equals Distance(a, b).
func Matrix(a, b string) [][]int {
	ra := []rune(a)
	rb := []rune(b)
	n := len(ra)
	m := len(rb)

	d := make([][]int, n+1)
	for i := 0; i <= n; i++ {
		d[i] = make([]int, m+1)
		d[i][0] = i
	}
	for j := 0; j <= m; j++ {
		d[0][j] = j
	}
	for i := 1; i <= n; i++ {
		for j := 1; j <= m; j++ {
			cost := 1
			if ra[i-1] == rb[j-1] {
				cost = 0
			}
			d[i][j] = min3(d[i][j-1]+1, d[i-1][j]+1, d[i-1][j-1]+cost)
		}
	}
	return d
}

// Similarity returns a 0..100 percentage of how similar a and b are, defined as
// (1 - distance/maxLen) * 100 rounded to the nearest integer. Two empty strings
// are considered 100% similar.
func Similarity(a, b string) int {
	la := len([]rune(a))
	lb := len([]rune(b))
	maxLen := la
	if lb > maxLen {
		maxLen = lb
	}
	if maxLen == 0 {
		return 100
	}
	dist := Distance(a, b)
	// Rounded percentage of matching characters.
	return ((maxLen-dist)*100 + maxLen/2) / maxLen
}

func min3(a, b, c int) int {
	m := a
	if b < m {
		m = b
	}
	if c < m {
		m = c
	}
	return m
}
