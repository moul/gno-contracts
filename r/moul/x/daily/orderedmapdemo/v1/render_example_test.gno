package orderedmapdemo

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Ordered Map
	//
	// A map that remembers insertion order, demoing the [`p/moul/x/daily/orderedmap`](/p/moul/x/daily/orderedmap/v1) library.
	//
	// ## Inserted
	//
	// `delta, alpha, charlie, bravo` → order kept as inserted, **not** sorted:
	//
	// | # | key | value |
	// |---|---|---|
	// | 1 | `delta` | `4` |
	// | 2 | `alpha` | `1` |
	// | 3 | `charlie` | `3` |
	// | 4 | `bravo` | `2` |
	//
	// ## After `Set("alpha", "99")`
	//
	// Updating keeps the original position — insertion order means *first* insertion:
	//
	// | # | key | value |
	// |---|---|---|
	// | 1 | `delta` | `4` |
	// | 2 | `alpha` | `99` |
	// | 3 | `charlie` | `3` |
	// | 4 | `bravo` | `2` |
	//
	// ## After deleting and re-adding `charlie`
	//
	// Re-inserting is a **new** insertion, so it goes last:
	//
	// | # | key | value |
	// |---|---|---|
	// | 1 | `delta` | `4` |
	// | 2 | `alpha` | `99` |
	// | 3 | `bravo` | `2` |
	// | 4 | `charlie` | `new` |
	//
	// > gno map iteration order is unspecified. A realm that ranges over a built-in map to build its page can emit a different page every call — a consensus bug, not a cosmetic one. This is the fix.
}
