package fenwickdemo

// ExampleRender pins the realm Render output as a testable example.
//
// The block below is copied verbatim from what gno printed, never hand
// typed: every figure in it is computed by the library under test, so a
// change in the tree shows up here as a diff rather than as prose.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Fenwick tree
	//
	// A Binary Indexed Tree: prefix sums and point updates both in `O(log n)`, demoing the [`p/moul/x/daily/fenwick`](/p/moul/x/daily/fenwick/v0) library.
	//
	// ## The values
	//
	// `3, 1, 4, 1, 5, 9, 2, 6` — 8 slots totalling `31`.
	//
	// ## Prefix sums
	//
	// | i | value | Prefix(i+1) |
	// | --- | --- | --- |
	// | 0 | 3 | 3 |
	// | 1 | 1 | 4 |
	// | 2 | 4 | 8 |
	// | 3 | 1 | 9 |
	// | 4 | 5 | 14 |
	// | 5 | 9 | 23 |
	// | 6 | 2 | 25 |
	// | 7 | 6 | 31 |
	//
	// ## Range queries
	//
	// | call | meaning | result |
	// | --- | --- | --- |
	// | `Range(2, 5)` | slots 2, 3, 4 | 10 |
	// | `Range(0, 8)` | everything | 31 |
	// | `Range(5, 5)` | empty | 0 |
	// | `Range(-9, 99)` | clamped to the ends | 31 |
	//
	// Reads clamp instead of panicking. A realm cannot be redeployed on the same path, so a `Render` that panics on an out-of-range index is a page that is broken for good. Writes do panic: a bad `Add` is a transaction, and aborting it is the useful answer.
	//
	// ## What the tree actually stores
	//
	// The array is not a copy of the values. Each internal slot holds the sum of a run of them, and the run lengths are the powers of two in the index. That is the whole trick, and `Covers` makes it visible.
	//
	// | node | covers slots | sum |
	// | --- | --- | --- |
	// | 1 | `[0, 1)` | 3 |
	// | 2 | `[0, 2)` | 4 |
	// | 3 | `[2, 3)` | 4 |
	// | 4 | `[0, 4)` | 9 |
	// | 5 | `[4, 5)` | 5 |
	// | 6 | `[4, 6)` | 14 |
	// | 7 | `[6, 7)` | 2 |
	// | 8 | `[0, 8)` | 31 |
	//
	// A prefix walk visits one node per set bit of the index, and those nodes tile the prefix exactly: no gap, no overlap. Eight slots means at most three nodes per query.
	//
	// ## The weighted draw
	//
	// `SearchPrefix(target)` names the slot that owns a target drawn below `Total`, in `O(log n)`. Each holder is picked in proportion to their stake, and a zero stake can never be picked at all.
	//
	// | holder | stake | owns targets | share |
	// | --- | --- | --- | --- |
	// | alice | 30 | `[0, 30)` | 30% |
	// | bob | 0 | none | 0% |
	// | carol | 45 | `[30, 75)` | 45% |
	// | dave | 5 | `[75, 80)` | 5% |
	// | erin | 20 | `[80, 100)` | 20% |
	//
	// | target | SearchPrefix | holder |
	// | --- | --- | --- |
	// | 0 | 0 | alice |
	// | 29 | 0 | alice |
	// | 30 | 2 | carol |
	// | 74 | 2 | carol |
	// | 99 | 4 | erin |
	//
	// Note target `30`: it is the first one past alice's share, and it skips bob entirely rather than landing on a holder with nothing staked. The search steps over zero-weight slots because their prefix does not advance, not because anything checks for them.
	//
	// ## Why not a plain slice
	//
	// Two obvious implementations each win one column and lose another. A realm whose scoreboard is written by every player and read by every page view pays both costs, which is where the middle row earns its keep.
	//
	// | structure | point update | prefix sum | weighted draw |
	// | --- | --- | --- | --- |
	// | plain slice | `O(1)` | `O(n)` | `O(n)` |
	// | **Fenwick tree** | `O(log n)` | `O(log n)` | `O(log n)` |
	// | running totals | `O(n)` | `O(1)` | `O(log n)` |
	//
	// The tree also carries no storage overhead: it is exactly `n` values, rearranged.
}
