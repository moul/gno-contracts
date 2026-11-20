package hilbertdemo

// ExampleRender pins the realm's root Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Hilbert curve
	//
	// Turning a point on a grid into one number that keeps neighbours together, demoing the [`p/moul/x/daily/hilbert`](/p/moul/x/daily/hilbert/v0) library.
	//
	// ## The curve, at order 3
	//
	// Each cell holds its index. Follow 0, 1, 2, 3 and you walk to a neighbouring cell every single time, never across the grid.
	//
	// ```
	// y=7  21 22 25 26 37 38 41 42
	// y=6  20 23 24 27 36 39 40 43
	// y=5  19 18 29 28 35 34 45 44
	// y=4  16 17 30 31 32 33 46 47
	// y=3  15 12 11 10 53 52 51 48
	// y=2  14 13  8  9 54 55 50 49
	// y=1   1  2  7  6 57 56 61 62
	// y=0   0  3  4  5 58 59 60 63
	//        0  1  2  3  4  5  6  7
	// ```
	//
	// Interleaving the bits of x and y, which is what a geohash does, also turns a point into one number. It jumps: at every power-of-two boundary two neighbouring cells land far apart in the key space. This curve never does, and every aligned sub-square of it is one unbroken run of indices.
	//
	// > Next: [`/box`](/r/moul/x/daily/hilbertdemo/v0:box) for the runs a box becomes, [`/keys`](/r/moul/x/daily/hilbertdemo/v0:keys) for what that is worth on a real grid.
}

// ExampleRender_box pins the page that turns a box into index runs.
func ExampleRender_box() {
	print(Render("/box"))
	// Output:
	// # Hilbert curve
	//
	// Turning a point on a grid into one number that keeps neighbours together, demoing the [`p/moul/x/daily/hilbert`](/p/moul/x/daily/hilbert/v0) library.
	//
	// ## A box is a few runs of indices
	//
	// An avl tree has one key, and a map has two dimensions. Keying the tree by the curve index makes "everything inside this box" a short list of range scans, storing no geometry and computing no distance.
	//
	// ```
	// 15  ................
	// 14  ................
	// 13  ......########..
	// 12  ......########..
	// 11  ......########..
	// 10  ......########..
	//  9  ......########..
	//  8  ......########..
	//  7  ......########..
	//  6  ......########..
	//  5  ................
	//  4  ................
	//  3  ................
	//  2  ................
	//  1  ................
	//  0  ................
	// ```
	//
	// The box (6,6)-(13,13) covers 6 runs:
	//
	// ```
	// 40 .. 43
	// 108 .. 115
	// 124 .. 147
	// 156 .. 163
	// 180 .. 187
	// 204 .. 215
	// ```
	//
	// Every index in those runs is inside the box and every cell of the box is in one of them, so a scan reads nothing it has to filter out.
	//
	// Move the same 8x8 box onto a power-of-two boundary, (8,8)-(15,15), and it collapses to 1 run: 128 .. 191. An aligned sub-square is always exactly one run, at every order.
	//
	// > Next: [`/keys`](/r/moul/x/daily/hilbertdemo/v0:keys) for the same question on a grid worth storing.
}

// ExampleRender_keys pins the comparison against a row-major key.
func ExampleRender_keys() {
	print(Render("/keys"))
	// Output:
	// # Hilbert curve
	//
	// Turning a point on a grid into one number that keeps neighbours together, demoing the [`p/moul/x/daily/hilbert`](/p/moul/x/daily/hilbert/v0) library.
	//
	// ## What it is worth on a real grid
	//
	// Order 16: 65536 cells on a side, 4294967296 in total. Three 16x16 windows, against the obvious alternative of a row-major key, `y*side + x`:
	//
	// | window | runs | keys spanned | row-major runs | row-major keys spanned |
	// | --- | --- | --- | --- | --- |
	// | (20000,20000)-(20015,20015) | 1 | 256 | 16 | 983056 |
	// | (1000,2000)-(1015,2015) | 2 | 896 | 16 | 983056 |
	// | (0,0)-(15,15) | 1 | 256 | 16 | 983056 |
	//
	// A row-major key puts one row of the grid next to the next row, so a window 16 rows tall always spans 15 whole rows of key space, however narrow it is. The curve spans something closer to the area of the window, because it never leaves a neighbourhood before finishing it.
	//
	// **It is not free and it is not always better.** On a grid barely bigger than the box, a badly placed window costs more runs than row-major would: at order 4 the window (5,5)-(10,10) is 9 runs against row-major's 6. The curve pays off when the window is small against the grid, which is the case a spatial index is for.
	//
	// > Back to [the curve](/r/moul/x/daily/hilbertdemo/v0) or [the box](/r/moul/x/daily/hilbertdemo/v0:box).
}
