// Package countminsketch estimates element frequencies in sublinear space, as
// a pure, reusable package.
//
// An exact frequency map costs one entry per distinct element, which on chain
// means unbounded storage driven by whatever users feed it. A Count-Min Sketch
// trades exactness for a FIXED footprint: d rows of w counters, sized once and
// never grown, regardless of how many distinct elements arrive.
//
// The error is one-sided and that is the whole contract: Estimate NEVER
// UNDERCOUNTS. Collisions can only add other elements' counts to a row, so the
// true frequency is always <= the estimate. Taking the minimum across d
// independent rows makes an overestimate require a collision in every row at
// once. Callers must treat the result as an upper bound — "at most this often",
// never "exactly this often".
//
// Sizing: width controls the error, depth controls the odds of hitting it.
// Roughly, the overestimate stays within total/width with probability
// 1 - (1/2)^depth.
//
// Hashing is FNV-1a with a per-row seed, computed in pure gno — deterministic
// across every node, which a map-address-derived hash would not be.
//
// A live demo of this package is at
// [r/moul/x/daily/countminsketchdemo](/r/moul/x/daily/countminsketchdemo/v1).
package countminsketch

import "errors"

const (
	// MinWidth/MaxWidth bound each row.
	MinWidth = 4
	MaxWidth = 8192
	// MinDepth/MaxDepth bound the number of rows.
	MinDepth = 1
	MaxDepth = 16
)

var (
	ErrBadWidth = errors.New("countminsketch: width out of range")
	ErrBadDepth = errors.New("countminsketch: depth out of range")
	ErrBadCount = errors.New("countminsketch: count must be positive")
)

// Sketch is a Count-Min Sketch over string elements.
type Sketch struct {
	width  int
	depth  int
	rows   [][]int64 // depth rows of width counters
	total  int64     // sum of every increment applied
	adds   int64     // number of Add/AddN calls applied
}

// New returns a sketch with the given dimensions.
func New(width, depth int) (*Sketch, error) {
	if width < MinWidth || width > MaxWidth {
		return nil, ErrBadWidth
	}
	if depth < MinDepth || depth > MaxDepth {
		return nil, ErrBadDepth
	}
	rows := make([][]int64, depth)
	for i := range rows {
		rows[i] = make([]int64, width)
	}
	return &Sketch{width: width, depth: depth, rows: rows}, nil
}

// NewDefault returns a sketch sized for general use: 256 x 4.
func NewDefault() *Sketch {
	s, _ := New(256, 4)
	return s
}

// Width returns the number of counters per row.
func (s *Sketch) Width() int { return s.width }

// Depth returns the number of rows.
func (s *Sketch) Depth() int { return s.depth }

// Counters returns the total number of counters — the fixed storage cost.
func (s *Sketch) Counters() int { return s.width * s.depth }

// Total returns the sum of every increment applied.
func (s *Sketch) Total() int64 { return s.total }

// Distinct is deliberately absent: a Count-Min Sketch cannot answer it. Use a
// HyperLogLog for cardinality.

// Add records one occurrence of e.
func (s *Sketch) Add(e string) { s.AddN(e, 1) }

// AddN records n occurrences of e. A non-positive n is ignored.
func (s *Sketch) AddN(e string, n int64) error {
	if n <= 0 {
		return ErrBadCount
	}
	for r := 0; r < s.depth; r++ {
		s.rows[r][s.index(e, r)] += n
	}
	s.total += n
	s.adds++
	return nil
}

// Estimate returns an UPPER BOUND on how often e was added. It never
// undercounts; it may overcount when every row collided.
func (s *Sketch) Estimate(e string) int64 {
	var min int64 = -1
	for r := 0; r < s.depth; r++ {
		v := s.rows[r][s.index(e, r)]
		if min < 0 || v < min {
			min = v
		}
	}
	if min < 0 {
		return 0
	}
	return min
}

// MightHave reports whether e may have been added. A false result is
// definitive: it was never added.
func (s *Sketch) MightHave(e string) bool { return s.Estimate(e) > 0 }

// Merge adds another sketch into this one. Both must have identical dimensions;
// merging is what makes sketches useful across shards or time windows.
func (s *Sketch) Merge(other *Sketch) error {
	if s.width != other.width {
		return ErrBadWidth
	}
	if s.depth != other.depth {
		return ErrBadDepth
	}
	for r := 0; r < s.depth; r++ {
		for c := 0; c < s.width; c++ {
			s.rows[r][c] += other.rows[r][c]
		}
	}
	s.total += other.total
	s.adds += other.adds
	return nil
}

// Reset zeroes every counter, keeping the dimensions.
func (s *Sketch) Reset() {
	for r := range s.rows {
		for c := range s.rows[r] {
			s.rows[r][c] = 0
		}
	}
	s.total = 0
	s.adds = 0
}

// Clone returns an independent copy.
func (s *Sketch) Clone() *Sketch {
	cp, _ := New(s.width, s.depth)
	for r := range s.rows {
		copy(cp.rows[r], s.rows[r])
	}
	cp.total = s.total
	cp.adds = s.adds
	return cp
}

// Row returns a copy of row r, for rendering and inspection.
func (s *Sketch) Row(r int) []int64 {
	if r < 0 || r >= s.depth {
		return nil
	}
	out := make([]int64, s.width)
	copy(out, s.rows[r])
	return out
}

// Index returns the column e maps to in row r — exported so a demo can show
// where collisions happen.
func (s *Sketch) Index(e string, r int) int {
	if r < 0 || r >= s.depth {
		return -1
	}
	return s.index(e, r)
}

// index hashes e for row r with FNV-1a, seeded per row.
func (s *Sketch) index(e string, row int) int {
	const (
		offset64 = uint64(14695981039346656037)
		prime64  = uint64(1099511628211)
	)
	h := offset64
	// Seed the row so each row hashes independently.
	h ^= uint64(row + 1)
	h *= prime64
	for i := 0; i < len(e); i++ {
		h ^= uint64(e[i])
		h *= prime64
	}
	return int(h % uint64(s.width))
}
