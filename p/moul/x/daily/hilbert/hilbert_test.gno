package hilbert

import "testing"

// golden3 is the order 3 curve, cell by cell, indexed by curve position. It
// comes from two independent constructions that agree on every cell through
// order 8: the published iterative pair, and a recursive one that places four
// transformed copies of the previous order. Nothing in this package produced
// it, which is the only way a golden table is worth having.
var golden3 = [][2]uint32{
	{0, 0}, {0, 1}, {1, 1}, {1, 0}, {2, 0}, {3, 0}, {3, 1}, {2, 1},
	{2, 2}, {3, 2}, {3, 3}, {2, 3}, {1, 3}, {1, 2}, {0, 2}, {0, 3},
	{0, 4}, {1, 4}, {1, 5}, {0, 5}, {0, 6}, {0, 7}, {1, 7}, {1, 6},
	{2, 6}, {2, 7}, {3, 7}, {3, 6}, {3, 5}, {2, 5}, {2, 4}, {3, 4},
	{4, 4}, {5, 4}, {5, 5}, {4, 5}, {4, 6}, {4, 7}, {5, 7}, {5, 6},
	{6, 6}, {6, 7}, {7, 7}, {7, 6}, {7, 5}, {6, 5}, {6, 4}, {7, 4},
	{7, 3}, {7, 2}, {6, 2}, {6, 3}, {5, 3}, {4, 3}, {4, 2}, {5, 2},
	{5, 1}, {4, 1}, {4, 0}, {5, 0}, {6, 0}, {6, 1}, {7, 1}, {7, 0},
}

func TestDecodeGolden(t *testing.T) {
	cases := []struct {
		name  string
		order int
		want  [][2]uint32
	}{
		{"order 0", 0, [][2]uint32{{0, 0}}},
		{"order 1", 1, [][2]uint32{{0, 0}, {0, 1}, {1, 1}, {1, 0}}},
		{"order 2", 2, [][2]uint32{
			{0, 0}, {1, 0}, {1, 1}, {0, 1},
			{0, 2}, {0, 3}, {1, 3}, {1, 2},
			{2, 2}, {2, 3}, {3, 3}, {3, 2},
			{3, 1}, {2, 1}, {2, 0}, {3, 0},
		}},
		{"order 3", 3, golden3},
	}
	for _, tc := range cases {
		for d, want := range tc.want {
			x, y, err := Decode(tc.order, uint64(d))
			if err != nil {
				t.Fatalf("%s: Decode(%d, %d) returned %v", tc.name, tc.order, d, err)
			}
			if x != want[0] || y != want[1] {
				t.Errorf("%s: Decode(%d, %d) = (%d, %d), want (%d, %d)",
					tc.name, tc.order, d, x, y, want[0], want[1])
			}
		}
	}
}

func TestEncodeGolden(t *testing.T) {
	for d, p := range golden3 {
		got, err := Encode(3, p[0], p[1])
		if err != nil {
			t.Fatalf("Encode(3, %d, %d) returned %v", p[0], p[1], err)
		}
		if got != uint64(d) {
			t.Errorf("Encode(3, %d, %d) = %d, want %d", p[0], p[1], got, d)
		}
	}
}

// TestRoundTrip walks every cell of every small order. The curve is a
// bijection between 0..4^order-1 and the grid, so a missed cell, a repeated
// cell and a broken round trip are three different failures and this catches
// all three.
func TestRoundTrip(t *testing.T) {
	for order := 0; order <= 6; order++ {
		side := Side(order)
		total := Length(order)
		seen := make([]bool, int(total))
		for d := uint64(0); d < total; d++ {
			x, y, err := Decode(order, d)
			if err != nil {
				t.Fatalf("order %d: Decode(%d) returned %v", order, d, err)
			}
			if x >= side || y >= side {
				t.Fatalf("order %d: Decode(%d) = (%d, %d), outside a %dx%d grid",
					order, d, x, y, side, side)
			}
			cell := int(y)*int(side) + int(x)
			if seen[cell] {
				t.Fatalf("order %d: cell (%d, %d) visited twice, at index %d", order, x, y, d)
			}
			seen[cell] = true
			back, err := Encode(order, x, y)
			if err != nil {
				t.Fatalf("order %d: Encode(%d, %d) returned %v", order, x, y, err)
			}
			if back != d {
				t.Fatalf("order %d: %d -> (%d, %d) -> %d", order, d, x, y, back)
			}
		}
	}
}

// TestAdjacent is the property that separates this curve from interleaving
// bits: consecutive indices are always neighbours on the grid, never a jump.
// A Z-order curve fails this at every power-of-two boundary.
func TestAdjacent(t *testing.T) {
	for order := 1; order <= 6; order++ {
		total := Length(order)
		px, py, _ := Decode(order, 0)
		for d := uint64(1); d < total; d++ {
			x, y, err := Decode(order, d)
			if err != nil {
				t.Fatalf("order %d: Decode(%d) returned %v", order, d, err)
			}
			if manhattan(px, x)+manhattan(py, y) != 1 {
				t.Fatalf("order %d: step %d jumps from (%d, %d) to (%d, %d)",
					order, d, px, py, x, y)
			}
			px, py = x, y
		}
	}
}

func manhattan(a, b uint32) uint32 {
	if a > b {
		return a - b
	}
	return b - a
}

func TestSideAndLength(t *testing.T) {
	cases := []struct {
		order      int
		side       uint32
		length     uint64
	}{
		{-1, 0, 0},
		{0, 1, 1},
		{1, 2, 4},
		{3, 8, 64},
		{16, 65536, 4294967296},
		{31, 2147483648, 4611686018427387904},
		{32, 0, 0},
	}
	for _, tc := range cases {
		if got := Side(tc.order); got != tc.side {
			t.Errorf("Side(%d) = %d, want %d", tc.order, got, tc.side)
		}
		if got := Length(tc.order); got != tc.length {
			t.Errorf("Length(%d) = %d, want %d", tc.order, got, tc.length)
		}
	}
}

func TestEncodeErrors(t *testing.T) {
	cases := []struct {
		name  string
		order int
		x, y  uint32
		want  error
	}{
		{"order below zero", -1, 0, 0, ErrOrder},
		{"order above MaxOrder", MaxOrder + 1, 0, 0, ErrOrder},
		{"x off the grid", 2, 4, 0, ErrPoint},
		{"y off the grid", 2, 0, 4, ErrPoint},
		{"last cell of order 0", 0, 0, 0, nil},
		{"x off a one-cell grid", 0, 1, 0, ErrPoint},
	}
	for _, tc := range cases {
		_, err := Encode(tc.order, tc.x, tc.y)
		if err != tc.want {
			t.Errorf("%s: Encode(%d, %d, %d) returned %v, want %v",
				tc.name, tc.order, tc.x, tc.y, err, tc.want)
		}
	}
}

func TestDecodeErrors(t *testing.T) {
	cases := []struct {
		name  string
		order int
		d     uint64
		want  error
	}{
		{"order below zero", -1, 0, ErrOrder},
		{"order above MaxOrder", MaxOrder + 1, 0, ErrOrder},
		{"index past the curve", 2, 16, ErrIndex},
		{"last index of order 2", 2, 15, nil},
		{"index past a one-cell curve", 0, 1, ErrIndex},
	}
	for _, tc := range cases {
		_, _, err := Decode(tc.order, tc.d)
		if err != tc.want {
			t.Errorf("%s: Decode(%d, %d) returned %v, want %v",
				tc.name, tc.order, tc.d, err, tc.want)
		}
	}
}

// TestRangesCoverExactly is the honest test of Ranges: it ignores how the
// ranges were built and asks only whether an index is covered exactly when
// its cell is inside the box. Both directions matter, since returning the
// whole curve would pass a test that only checks the box is covered.
func TestRangesCoverExactly(t *testing.T) {
	const order = 4
	side := Side(order)
	boxes := [][4]uint32{
		{0, 0, 0, 0},
		{0, 0, 15, 15},
		{3, 2, 6, 9},
		{8, 8, 11, 11},
		{15, 0, 15, 15},
		{0, 7, 15, 8},
		{5, 5, 5, 9},
	}
	for _, b := range boxes {
		ranges, err := Ranges(order, b[0], b[1], b[2], b[3])
		if err != nil {
			t.Fatalf("Ranges%v returned %v", b, err)
		}
		for d := uint64(0); d < Length(order); d++ {
			x, y, _ := Decode(order, d)
			inBox := x >= b[0] && x <= b[2] && y >= b[1] && y <= b[3]
			if covered(ranges, d) != inBox {
				t.Errorf("Ranges%v: index %d at (%d, %d) covered=%v, inBox=%v",
					b, d, x, y, covered(ranges, d), inBox)
			}
		}
		_ = side
	}
}

// TestRangesAreMergedAndSorted pins the shape of the result, which is what a
// caller scanning an avl tree depends on: ascending, disjoint, and never two
// ranges that touch, since those would be one scan and not two.
func TestRangesAreMergedAndSorted(t *testing.T) {
	ranges, err := Ranges(4, 3, 2, 9, 11)
	if err != nil {
		t.Fatalf("Ranges returned %v", err)
	}
	if len(ranges) == 0 {
		t.Fatal("Ranges returned nothing for a non-empty box")
	}
	for i, r := range ranges {
		if r.Lo > r.Hi {
			t.Errorf("range %d is reversed: %d..%d", i, r.Lo, r.Hi)
		}
		if i > 0 && r.Lo <= ranges[i-1].Hi+1 {
			t.Errorf("range %d (%d..%d) touches or overlaps range %d (%d..%d)",
				i, r.Lo, r.Hi, i-1, ranges[i-1].Lo, ranges[i-1].Hi)
		}
	}
}

// TestRangesBeatRowMajor states the reason to key a tree this way at all. A
// row-major index needs one scan per row of the box, always. The curve needs
// fewer, because it keeps a 2-D neighbourhood contiguous in 1-D.
func TestRangesBeatRowMajor(t *testing.T) {
	const order = 5
	ranges, err := Ranges(order, 8, 8, 15, 15)
	if err != nil {
		t.Fatalf("Ranges returned %v", err)
	}
	if len(ranges) != 1 {
		t.Errorf("an aligned 8x8 box at order %d needs %d scans, want 1", order, len(ranges))
	}
	ranges, err = Ranges(order, 6, 6, 13, 13)
	if err != nil {
		t.Fatalf("Ranges returned %v", err)
	}
	const rowMajorScans = 8 // one per row of an 8-row box, whatever the box
	if len(ranges) >= rowMajorScans {
		t.Errorf("an unaligned 8x8 box needs %d scans, want fewer than the %d a row-major index needs",
			len(ranges), rowMajorScans)
	}
}

func TestRangesErrors(t *testing.T) {
	cases := []struct {
		name           string
		order          int
		x0, y0, x1, y1 uint32
		want           error
	}{
		{"bad order", 40, 0, 0, 1, 1, ErrOrder},
		{"x reversed", 4, 5, 0, 2, 1, ErrBox},
		{"y reversed", 4, 0, 5, 1, 2, ErrBox},
		{"corner off the grid", 2, 0, 0, 4, 1, ErrPoint},
		{"box too large", 10, 0, 0, 511, 511, ErrTooLarge},
		{"largest box allowed", 8, 0, 0, 255, 255, nil},
	}
	for _, tc := range cases {
		_, err := Ranges(tc.order, tc.x0, tc.y0, tc.x1, tc.y1)
		if err != tc.want {
			t.Errorf("%s: Ranges(%d, %d, %d, %d, %d) returned %v, want %v",
				tc.name, tc.order, tc.x0, tc.y0, tc.x1, tc.y1, err, tc.want)
		}
	}
}

// TestLargeOrder checks the arithmetic at the top of the range, where a 32-bit
// coordinate and a 62-bit index are both near their limit and an intermediate
// that overflows would still look plausible at small orders.
func TestLargeOrder(t *testing.T) {
	cases := []struct {
		order int
		x, y  uint32
	}{
		{31, 0, 0},
		{31, 2147483647, 2147483647},
		{31, 2147483647, 0},
		{31, 0, 2147483647},
		{31, 1234567890, 987654321},
		{16, 65535, 65535},
	}
	for _, tc := range cases {
		d, err := Encode(tc.order, tc.x, tc.y)
		if err != nil {
			t.Fatalf("Encode(%d, %d, %d) returned %v", tc.order, tc.x, tc.y, err)
		}
		if d >= Length(tc.order) {
			t.Errorf("Encode(%d, %d, %d) = %d, past the %d cells of the curve",
				tc.order, tc.x, tc.y, d, Length(tc.order))
		}
		x, y, err := Decode(tc.order, d)
		if err != nil {
			t.Fatalf("Decode(%d, %d) returned %v", tc.order, d, err)
		}
		if x != tc.x || y != tc.y {
			t.Errorf("order %d: (%d, %d) -> %d -> (%d, %d)", tc.order, tc.x, tc.y, d, x, y)
		}
	}
}

func covered(ranges []Range, d uint64) bool {
	for _, r := range ranges {
		if d >= r.Lo && d <= r.Hi {
			return true
		}
	}
	return false
}
