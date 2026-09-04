package flatmapdemo

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Flat Map
	//
	// A map backed by sorted slices, demoing the [`p/moul/x/daily/flatmap`](/p/moul/x/daily/flatmap/v1) library.
	//
	// ## Sorted by construction
	//
	// Inserted as `delta, alpha, echo, bravo, charlie` — stored sorted:
	//
	// | # | key | value |
	// |---|---|---|
	// | 0 | `alpha` | `2` |
	// | 1 | `bravo` | `4` |
	// | 2 | `charlie` | `5` |
	// | 3 | `delta` | `1` |
	// | 4 | `echo` | `3` |
	//
	// No sort on read, and no dependence on map iteration order — which gno leaves unspecified, and which would let two nodes render different pages from the same state.
	//
	// ## Indexed access
	//
	// Sorted storage gives positional lookup that a hash map cannot:
	//
	// - `At(0)` → `alpha` = `2`
	// - `At(2)` → `charlie` = `5`
	// - `At(4)` → `echo` = `3`
	//
	// ## Range queries
	//
	// Two binary searches and a walk — `lo` inclusive, `hi` exclusive:
	//
	// | range | keys |
	// |---|---|
	// | `["bravo", "delta")` | `bravo`, `charlie` |
	// | `["charlie", ∞)` | `charlie`, `delta`, `echo` |
	// | `["b", "d")` | `bravo`, `charlie` |
	//
	// The last one asks for bounds that are not keys at all — the search still lands in the right place.
	//
	// ## The trade
	//
	// | operation | cost |
	// |---|---|
	// | `Get` | O(log n) binary search over contiguous memory |
	// | iteration | O(n), already ordered, nothing to sort |
	// | `Set` in the middle | **O(n)** — the tail shifts |
	// | `Set` at the end | O(1) amortised — the fast path |
	//
	// Cheap reads and cheap ordered iteration, paid for at write time.
}
