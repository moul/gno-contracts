package bwt

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestTransform(t *testing.T) {
	cases := []struct {
		name string
		in   string
		last string
		idx  int
	}{
		{"empty", "", "", 0},
		{"single", "a", "a", 0},
		{"banana", "banana", "nnbaaa", 3},
		{"all equal", "aaa", "aaa", 0},
		{"alternating", "abab", "bbaa", 0},
		{"abracadabra", "abracadabra", "rdarcaaaabb", 2},
		{"sentinel free", "^BANANA|", "BNN^AA|A", 6},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			last, idx, err := Transform(tc.in)
			uassert.NoError(t, err)
			uassert.Equal(t, tc.last, last)
			uassert.Equal(t, tc.idx, idx)
		})
	}
}

func TestRoundTrip(t *testing.T) {
	cases := []string{
		"",
		"a",
		"ab",
		"banana",
		"mississippi",
		"the quick brown fox jumps over the lazy dog",
		"aaaaaaaaaa",
		"abababababab",
		"\x00\xff\x7f\x80",
		strings.Repeat("na", 64) + " batman",
	}
	for _, in := range cases {
		last, idx, err := Transform(in)
		uassert.NoError(t, err)
		got, err := Inverse(last, idx)
		uassert.NoError(t, err)
		uassert.Equal(t, in, got)
	}
}

// TestTransformIsAPermutation pins the property that makes BWT usable as a
// preprocessing step: the output has the same bytes as the input, in a
// different order, so nothing downstream has to widen its alphabet.
func TestTransformIsAPermutation(t *testing.T) {
	const in = "mississippi river"
	last, _, err := Transform(in)
	uassert.NoError(t, err)
	uassert.Equal(t, len(in), len(last))
	for _, c := range []byte("misp rve") {
		uassert.Equal(t, strings.Count(in, string(c)), strings.Count(last, string(c)))
	}
}

// TestRunsClustering pins the whole point of the transform: equal bytes end up
// adjacent, so a run-length coder downstream has fewer, longer runs to encode.
func TestRunsClustering(t *testing.T) {
	const in = "banana bandana bandanna"
	last, _, err := Transform(in)
	uassert.NoError(t, err)
	uassert.Equal(t, 22, Runs(in))
	uassert.Equal(t, 11, Runs(last))
}

// TestRunsNotAlwaysBetter pins the counter-example, so nobody reads the one
// above as a guarantee. "mississippi" repeats letters but no substring long
// enough to group, and the transform buys exactly nothing on it.
func TestRunsNotAlwaysBetter(t *testing.T) {
	const in = "mississippi"
	last, _, err := Transform(in)
	uassert.NoError(t, err)
	uassert.Equal(t, "pssmipissii", last)
	uassert.Equal(t, Runs(in), Runs(last))
}

func TestRuns(t *testing.T) {
	cases := []struct {
		in   string
		want int
	}{
		{"", 0},
		{"a", 1},
		{"aaa", 1},
		{"ab", 2},
		{"aabba", 3},
		{"banana", 6},
	}
	for _, tc := range cases {
		uassert.Equal(t, tc.want, Runs(tc.in))
	}
}

func TestTransformTooLong(t *testing.T) {
	_, _, err := Transform(strings.Repeat("a", MaxLen+1))
	uassert.ErrorIs(t, err, ErrTooLong)
}

func TestInverseTooLong(t *testing.T) {
	_, err := Inverse(strings.Repeat("a", MaxLen+1), 0)
	uassert.ErrorIs(t, err, ErrTooLong)
}

// TestInverseBadIndex pins that the index is validated rather than used to
// walk off the end of the last column: it arrives from a caller, and on an
// empty string the only valid index is 0.
func TestInverseBadIndex(t *testing.T) {
	cases := []struct {
		name string
		last string
		idx  int
	}{
		{"past end", "nnbaaa", 6},
		{"negative", "nnbaaa", -1},
		{"empty with index", "", 1},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := Inverse(tc.last, tc.idx)
			uassert.ErrorIs(t, err, ErrBadIndex)
		})
	}
}

// TestInverseIsTotal pins that no last column plus in-range index can panic.
// Inverse runs inside a realm's Render, where a panic is a permanently
// unreadable page, so it must return a string for every input it accepts.
func TestInverseIsTotal(t *testing.T) {
	for _, last := range []string{"zzzz", "abcd", "\x00\x00\xff", "||||"} {
		for idx := 0; idx < len(last); idx++ {
			got, err := Inverse(last, idx)
			uassert.NoError(t, err)
			uassert.Equal(t, len(last), len(got))
		}
	}
}

func TestMatrix(t *testing.T) {
	rows, idx, err := Matrix("banana")
	uassert.NoError(t, err)
	uassert.Equal(t, 3, idx)
	want := []string{"abanan", "anaban", "ananab", "banana", "nabana", "nanaba"}
	uassert.Equal(t, len(want), len(rows))
	for i, w := range want {
		uassert.Equal(t, w, rows[i])
	}
}

// TestMatrixAgreesWithTransform pins that the display helper and the transform
// cannot drift: the last column of the matrix IS the transform, and a demo
// that rendered a matrix disagreeing with the string beside it would be worse
// than one that rendered no matrix.
func TestMatrixAgreesWithTransform(t *testing.T) {
	for _, in := range []string{"", "a", "banana", "abab", "mississippi"} {
		rows, mIdx, err := Matrix(in)
		uassert.NoError(t, err)
		last, tIdx, err := Transform(in)
		uassert.NoError(t, err)
		uassert.Equal(t, tIdx, mIdx)
		got := ""
		for _, r := range rows {
			got += string(r[len(r)-1])
		}
		uassert.Equal(t, last, got)
	}
}

func TestMatrixTooLong(t *testing.T) {
	_, _, err := Matrix(strings.Repeat("a", MaxMatrixLen+1))
	uassert.ErrorIs(t, err, ErrTooLong)
}
