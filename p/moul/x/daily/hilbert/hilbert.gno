// Package hilbert maps a point on a square grid to a single number and back,
// along the Hilbert curve: the space-filling curve that never jumps.
//
// The reason to want one on chain is that a realm has exactly one cheap index,
// an avl tree over a single key, and a map is two-dimensional. Keying the tree
// by the curve index turns "everything inside this box" into a handful of
// range scans, with no geometry stored and no distance computed:
//
//	d, _ := hilbert.Encode(16, x, y)       // the key you store
//	rs, _ := hilbert.Ranges(16, 10, 10, 20, 20)
//	for _, r := range rs {                 // one tree.Iterate per range
//		// scan r.Lo .. r.Hi
//	}
//
// Interleaving the bits of x and y, which is what a geohash does, gives the
// Z-order curve and also turns a point into one number. The difference is the
// jump: Z-order leaps across the grid at every power-of-two boundary, so two
// neighbouring cells can land at opposite ends of the key space. The Hilbert
// curve has no jumps at all. Consecutive indices are always neighbouring
// cells, every aligned sub-square is one contiguous run of indices, and that
// is what makes a box cost few scans instead of one per row.
//
// Everything here is integer arithmetic on powers of two. No float, no map
// iteration, nothing to round, so two identical calls cannot disagree and a
// Render built on it is deterministic.
//
// The curve is the published iterative construction, ported as is. It was
// checked cell by cell against a second, recursive construction over all
// 65536 cells of order 8 before being written down.
//
// A live demo of this package is at
// [r/moul/x/daily/hilbertdemo](/r/moul/x/daily/hilbertdemo/v0).
package hilbert

import "errors"

// MaxOrder is the largest order this package handles. An order n curve covers
// a 2^n by 2^n grid with 4^n cells, so order 31 is the last one whose side
// still fits a uint32 and whose index still fits a uint64.
const MaxOrder = 31

// MaxBoxCells caps how many cells Ranges will walk. Ranges is proportional to
// the area of the box, not to its perimeter, so the cap is what stops a caller
// from asking a realm to visit four billion cells inside one transaction.
const MaxBoxCells = 1 << 16

var (
	// ErrOrder is returned for an order outside 0..MaxOrder.
	ErrOrder = errors.New("hilbert: order out of range")
	// ErrPoint is returned for a coordinate at or past the side of the grid.
	ErrPoint = errors.New("hilbert: point outside the grid")
	// ErrIndex is returned for an index at or past the length of the curve.
	ErrIndex = errors.New("hilbert: index outside the curve")
	// ErrBox is returned by Ranges when a corner is past the opposite one.
	ErrBox = errors.New("hilbert: box corners are reversed")
	// ErrTooLarge is returned by Ranges for a box of more than MaxBoxCells.
	ErrTooLarge = errors.New("hilbert: box has more cells than MaxBoxCells")
)

// Range is an inclusive run of curve indices, as a tree scan would take it:
// Lo and Hi are both inside the box the Range came from.
type Range struct {
	Lo uint64
	Hi uint64
}

// Side returns the width of an order n grid, 2^order, or 0 for an order
// outside 0..MaxOrder. It returns rather than fails so that a Render can ask
// without a branch: a zero side names no valid cell.
func Side(order int) uint32 {
	if order < 0 || order > MaxOrder {
		return 0
	}
	return uint32(1) << uint(order)
}

// Length returns the number of cells on an order n curve, 4^order, or 0 for an
// order outside 0..MaxOrder. Indices run from 0 to Length-1.
func Length(order int) uint64 {
	if order < 0 || order > MaxOrder {
		return 0
	}
	return uint64(1) << uint(2*order)
}

// Encode returns the curve index of the cell at (x, y) on an order n grid.
// It is the inverse of Decode, and it reports ErrPoint rather than wrapping or
// clamping a coordinate that is off the grid, because a silently clamped point
// becomes a wrong key that nothing downstream can detect.
func Encode(order int, x, y uint32) (uint64, error) {
	side := Side(order)
	if side == 0 {
		return 0, ErrOrder
	}
	if x >= side || y >= side {
		return 0, ErrPoint
	}
	var d uint64
	for s := side >> 1; s > 0; s >>= 1 {
		var rx, ry uint32
		if x&s > 0 {
			rx = 1
		}
		if y&s > 0 {
			ry = 1
		}
		// The quadrant this bit selects contributes a whole sub-square of
		// indices, and (3*rx)^ry is which of the four it is along the curve.
		d += uint64(s) * uint64(s) * uint64((3*rx)^ry)
		x, y = rotate(side, x, y, rx, ry)
	}
	return d, nil
}

// Decode returns the cell at index d on an order n curve. It is the inverse of
// Encode.
func Decode(order int, d uint64) (uint32, uint32, error) {
	side := Side(order)
	if side == 0 {
		return 0, 0, ErrOrder
	}
	if d >= Length(order) {
		return 0, 0, ErrIndex
	}
	var x, y uint32
	t := d
	for s := uint32(1); s < side; s <<= 1 {
		rx := uint32(1 & (t >> 1))
		ry := uint32(1 & (t ^ uint64(rx)))
		x, y = rotate(s, x, y, rx, ry)
		x += s * rx
		y += s * ry
		t >>= 2
	}
	return x, y, nil
}

// rotate reflects and transposes a sub-square so that the four quadrants of
// the curve join end to end. This is the whole difference between a Hilbert
// curve and interleaved bits: without it the curve jumps between quadrants.
func rotate(n, x, y, rx, ry uint32) (uint32, uint32) {
	if ry != 0 {
		return x, y
	}
	if rx == 1 {
		x = n - 1 - x
		y = n - 1 - y
	}
	return y, x
}

// Ranges returns the curve indices covered by the box from (x0, y0) to
// (x1, y1) inclusive, as ascending, disjoint, non-touching runs. Scanning
// every returned Range visits exactly the cells of the box and no others,
// which is what makes it safe to hand straight to a tree iteration.
//
// The cost is proportional to the area of the box, so a box larger than
// MaxBoxCells is refused rather than served slowly. A realm answering window
// queries over a big grid wants a coarse order for the key and a fine one
// inside the value, not a single order fine enough to need a huge box.
func Ranges(order int, x0, y0, x1, y1 uint32) ([]Range, error) {
	side := Side(order)
	if side == 0 {
		return nil, ErrOrder
	}
	if x0 > x1 || y0 > y1 {
		return nil, ErrBox
	}
	if x1 >= side || y1 >= side {
		return nil, ErrPoint
	}
	cells := (uint64(x1-x0) + 1) * (uint64(y1-y0) + 1)
	if cells > MaxBoxCells {
		return nil, ErrTooLarge
	}

	ds := make([]uint64, 0, int(cells))
	for y := y0; y <= y1; y++ {
		for x := x0; x <= x1; x++ {
			d, err := Encode(order, x, y)
			if err != nil {
				return nil, err
			}
			ds = append(ds, d)
		}
	}
	sortIndices(ds)

	out := make([]Range, 0, 8)
	out = append(out, Range{Lo: ds[0], Hi: ds[0]})
	for i := 1; i < len(ds); i++ {
		last := len(out) - 1
		if ds[i] == out[last].Hi+1 {
			out[last].Hi = ds[i]
			continue
		}
		out = append(out, Range{Lo: ds[i], Hi: ds[i]})
	}
	return out, nil
}

// sortIndices sorts in place, bottom up, with one scratch buffer. A merge sort
// rather than an insertion sort because MaxBoxCells is 65536 and the quadratic
// one would be the whole gas budget; bottom up rather than recursive because
// the depth is then a loop bound and not a call stack.
func sortIndices(a []uint64) {
	n := len(a)
	if n < 2 {
		return
	}
	buf := make([]uint64, n)
	for width := 1; width < n; width *= 2 {
		for lo := 0; lo < n; lo += 2 * width {
			mid := lo + width
			if mid > n {
				mid = n
			}
			hi := lo + 2*width
			if hi > n {
				hi = n
			}
			mergeRuns(a, buf, lo, mid, hi)
		}
		copy(a, buf)
	}
}

// mergeRuns merges the sorted runs a[lo:mid] and a[mid:hi] into buf[lo:hi].
func mergeRuns(a, buf []uint64, lo, mid, hi int) {
	i, j := lo, mid
	for k := lo; k < hi; k++ {
		if i >= mid {
			buf[k] = a[j]
			j++
			continue
		}
		if j >= hi || a[i] <= a[j] {
			buf[k] = a[i]
			i++
			continue
		}
		buf[k] = a[j]
		j++
	}
}
