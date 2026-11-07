package segmenttreedemo

// ExampleRender pins the realm's root Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Segment tree
	//
	// Sum, minimum and maximum over any window of the same slots, each in `O(log n)`, with any single slot rewritable in `O(log n)` too. Demoing the [`p/moul/x/daily/segmenttree`](/p/moul/x/daily/segmenttree/v0) library.
	//
	// ## The slots
	//
	// `3 1 4 1 5 9 2 6`, 8 of them.
	//
	// ## Three questions, one walk
	//
	// | window | sum | min | max |
	// | --- | --- | --- | --- |
	// | `[0,8)` | 31 | 1 | 9 |
	// | `[0,4)` | 9 | 1 | 4 |
	// | `[4,8)` | 22 | 2 | 9 |
	// | `[2,6)` | 19 | 1 | 9 |
	// | `[5,6)` | 9 | 9 | 9 |
	// | `[3,3)` | _empty_ | _empty_ | _empty_ |
	//
	// The last row is empty, and the library says so rather than returning the identity: `min` over no slots would otherwise read `9223372036854775807`, which is a number a page should never print.
	//
	// ## The tree the sums are read off
	//
	// ```
	// L0 [0,8)=31
	// L1 [0,4)=9     [4,8)=22
	// L2 [0,2)=4     [2,4)=5     [4,6)=14    [6,8)=8
	// L3 [0,1)=3     [1,2)=1     [2,3)=4     [3,4)=1     [4,5)=5     [5,6)=9     [6,7)=2     [7,8)=6
	// ```
	//
	// Each node holds the sum of the range beside it, so a window is answered by at most two nodes per level rather than by 8 additions.
	//
	// > See [`/update`](/r/moul/x/daily/segmenttreedemo/v0:update) for what one write repairs.
}

// ExampleRender_update pins the point-update page: the same structure after
// one slot is rewritten, which is the half a prefix-sum array cannot do.
func ExampleRender_update() {
	print(Render("/update"))
	// Output:
	// # Segment tree
	//
	// Sum, minimum and maximum over any window of the same slots, each in `O(log n)`, with any single slot rewritable in `O(log n)` too. Demoing the [`p/moul/x/daily/segmenttree`](/p/moul/x/daily/segmenttree/v0) library.
	//
	// ## One write
	//
	// Slot `5` goes from `9` to `0`.
	//
	// | window `[4,8)` | before | after |
	// | --- | --- | --- |
	// | sum | 22 | 13 |
	// | min | 2 | 0 |
	//
	// ## What it cost
	//
	// The tree is 4 levels deep, so the write repaired 3 parent nodes and left the other 11 alone. A prefix-sum array would have answered the window faster and then rewritten every slot after this one.
	//
	// ```
	// L0 [0,8)=22
	// L1 [0,4)=9     [4,8)=13
	// L2 [0,2)=4     [2,4)=5     [4,6)=5     [6,8)=8
	// L3 [0,1)=3     [1,2)=1     [2,3)=4     [3,4)=1     [4,5)=5     [5,6)=0     [6,7)=2     [7,8)=6
	// ```
	//
	// > Back to [the root page](/r/moul/x/daily/segmenttreedemo/v0).
}
