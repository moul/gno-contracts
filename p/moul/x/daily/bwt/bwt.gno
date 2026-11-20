// Package bwt implements the Burrows-Wheeler transform as a pure, reusable
// package: a reversible permutation of a string that groups equal bytes
// together, so a run-length or entropy coder downstream has less work to do.
//
// It compresses nothing on its own. [Transform] returns the same bytes it was
// given, in a different order, plus the one integer [Inverse] needs to undo it.
// That is the whole contract, and it is why BWT is a *preprocessing* step:
// bzip2 runs it before move-to-front and Huffman, and the clustering is where
// the ratio comes from.
//
// The clustering is a tendency, not a guarantee. [Runs] counts maximal runs of
// equal bytes so a caller can check rather than assume: "banana bandana
// bandanna" drops from 22 runs to 11, and "mississippi" does not move at all,
// because it repeats letters but no substring long enough to group.
//
// Round-tripping is total within [MaxLen]: every string [Transform] accepts
// comes back from [Inverse] unchanged, including the empty string and bytes
// outside ASCII, because no sentinel byte is appended and so no byte is
// reserved.
//
// A live demo of this package is at
// [r/moul/x/daily/bwtdemo](/r/moul/x/daily/bwtdemo/v0).
package bwt

import (
	"errors"
	"sort"
)

// MaxLen bounds input so transform gas stays predictable.
//
// It is small on purpose. Sorting the rotations costs O(n log n) comparisons
// and a comparison walks up to n bytes, so the work is quadratic in the input:
// at 256 bytes the worst case is already around half a million byte
// comparisons, and the degenerate input that reaches it ("aaaa...") is the one
// a caller is most likely to try first.
const MaxLen = 256

var (
	// ErrTooLong is returned when input exceeds MaxLen.
	ErrTooLong = errors.New("bwt: input too long")
	// ErrBadIndex is returned when the index handed to Inverse does not name a
	// row of the last column it was given.
	ErrBadIndex = errors.New("bwt: index out of range")
)

// Transform returns the last column of the sorted rotation matrix of s, and
// the row at which s itself landed.
//
// Both values are needed to invert it. The index is how this variant avoids
// appending a sentinel byte: a sentinel would have to be a byte the input can
// never contain, and there is no such byte in an arbitrary string.
func Transform(s string) (string, int, error) {
	if len(s) > MaxLen {
		return "", 0, ErrTooLong
	}
	n := len(s)
	if n == 0 {
		return "", 0, nil
	}

	idx := make([]int, n)
	for i := 0; i < n; i++ {
		idx[i] = i
	}
	// Stable, so two equal rotations keep their input order and two runs over
	// the same string can never disagree about the index. A Render that moved
	// between nodes would not be a Render.
	sort.Stable(&rotations{s: s, idx: idx})

	out := make([]byte, n)
	primary := 0
	for row := 0; row < n; row++ {
		start := idx[row]
		// The last byte of the rotation starting at start, which is the byte
		// just before it in s, wrapping.
		out[row] = s[(start+n-1)%n]
		if start == 0 {
			primary = row
		}
	}
	return string(out), primary, nil
}

// Inverse rebuilds the string whose Transform produced last and idx.
//
// It never reconstructs the rotation matrix: the first column is the last one
// sorted, and the i-th occurrence of a byte in the last column is the i-th
// occurrence of that byte in the first, which is enough to walk the original
// string backwards one byte at a time in O(n).
func Inverse(last string, idx int) (string, error) {
	if len(last) > MaxLen {
		return "", ErrTooLong
	}
	n := len(last)
	if n == 0 {
		if idx != 0 {
			return "", ErrBadIndex
		}
		return "", nil
	}
	if idx < 0 || idx >= n {
		return "", ErrBadIndex
	}

	// rank[i] is how many times last[i] occurred before position i, and count
	// ends up holding the total per byte.
	var count [256]int
	rank := make([]int, n)
	for i := 0; i < n; i++ {
		c := last[i]
		rank[i] = count[c]
		count[c]++
	}
	// first[c] is where c starts in the first column, which is last sorted.
	var first [256]int
	sum := 0
	for c := 0; c < 256; c++ {
		first[c] = sum
		sum += count[c]
	}

	out := make([]byte, n)
	row := idx
	for k := n - 1; k >= 0; k-- {
		c := last[row]
		out[k] = c
		row = first[c] + rank[row]
	}
	return string(out), nil
}

// MaxMatrixLen bounds [Matrix], and it is far below [MaxLen] on purpose:
// Matrix materialises every rotation, so it allocates n squared bytes where
// Transform allocates n. At 64 that is 4 KiB, which is also about as many
// rows as anyone can read.
const MaxMatrixLen = 64

// Matrix returns the sorted rotation matrix of s and the row s itself landed
// on, for showing the transform rather than performing it.
//
// It is a teaching and debugging aid, not a step in the transform: [Transform]
// never builds this and a caller that only wants the result should not either.
// The last column of what Matrix returns is exactly what Transform returns,
// which is the property worth relying on.
func Matrix(s string) ([]string, int, error) {
	if len(s) > MaxMatrixLen {
		return nil, 0, ErrTooLong
	}
	n := len(s)
	if n == 0 {
		return nil, 0, nil
	}

	idx := make([]int, n)
	for i := 0; i < n; i++ {
		idx[i] = i
	}
	sort.Stable(&rotations{s: s, idx: idx})

	rows := make([]string, n)
	primary := 0
	for row := 0; row < n; row++ {
		start := idx[row]
		rows[row] = s[start:] + s[:start]
		if start == 0 {
			primary = row
		}
	}
	return rows, primary, nil
}

// Runs counts maximal runs of equal bytes, so a caller can measure what the
// transform bought instead of assuming it bought anything. Fewer runs over the
// same length means longer runs, which is exactly what a run-length coder is
// paid by.
func Runs(s string) int {
	if len(s) == 0 {
		return 0
	}
	n := 1
	for i := 1; i < len(s); i++ {
		if s[i] != s[i-1] {
			n++
		}
	}
	return n
}

// rotations sorts rotation start offsets without materialising the rotations.
// Building the n strings of length n would be the obvious implementation and
// it allocates n squared bytes, which at MaxLen is 64 KiB of garbage to sort a
// 256-byte string.
type rotations struct {
	s   string
	idx []int
}

func (r *rotations) Len() int { return len(r.idx) }

func (r *rotations) Swap(i, j int) { r.idx[i], r.idx[j] = r.idx[j], r.idx[i] }

func (r *rotations) Less(i, j int) bool {
	a, b := r.idx[i], r.idx[j]
	if a == b {
		return false
	}
	n := len(r.s)
	for k := 0; k < n; k++ {
		ca := r.s[(a+k)%n]
		cb := r.s[(b+k)%n]
		if ca != cb {
			return ca < cb
		}
	}
	return false // the two rotations are equal, which a periodic string has
}
