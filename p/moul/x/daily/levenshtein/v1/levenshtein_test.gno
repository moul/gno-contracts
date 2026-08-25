package levenshtein

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestDistance(t *testing.T) {
	cases := []struct {
		a, b string
		want int
	}{
		{"", "", 0},
		{"abc", "", 3},
		{"", "abc", 3},
		{"abc", "abc", 0},
		{"kitten", "sitting", 3},
		{"flaw", "lawn", 2},
		{"sunday", "saturday", 3},
		{"gno", "gnoland", 4},
		{"book", "back", 2},
		// Rune-aware: each accented char is one edit, not several bytes.
		{"café", "cafe", 1},
		{"héllo", "hello", 1},
	}
	for _, tc := range cases {
		got := Distance(tc.a, tc.b)
		uassert.Equal(t, tc.want, got)
		// Symmetry: distance is the same in both directions.
		uassert.Equal(t, tc.want, Distance(tc.b, tc.a))
	}
}

func TestSimilarity(t *testing.T) {
	// Identical strings.
	uassert.Equal(t, 100, Similarity("hello", "hello"))
	// Both empty.
	uassert.Equal(t, 100, Similarity("", ""))
	// Completely different lengths / content.
	uassert.Equal(t, 0, Similarity("abc", "xyz"))
	// kitten/sitting: max len 7, distance 3 -> round((4/7)*100) = 57.
	uassert.Equal(t, 57, Similarity("kitten", "sitting"))
}

func TestMatrix(t *testing.T) {
	d := Matrix("kitten", "sitting")
	// Dimensions: (6+1) x (7+1).
	uassert.Equal(t, 7, len(d))
	uassert.Equal(t, 8, len(d[0]))
	// First row and column are the identity ramps.
	for j := 0; j <= 7; j++ {
		uassert.Equal(t, j, d[0][j])
	}
	for i := 0; i <= 6; i++ {
		uassert.Equal(t, i, d[i][0])
	}
	// Bottom-right cell equals Distance.
	uassert.Equal(t, Distance("kitten", "sitting"), d[6][7])
}
