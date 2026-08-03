package bloomfilter

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Bloom Filter
	//
	// A probabilistic set membership test: `Add` an item, then `MightContain` it back. False positives are possible; false negatives never happen. The filter never stores the items themselves — only 2048 bits.
	//
	// ## Stats
	//
	// - **Bits (m):** 2048
	// - **Hash functions (k):** 5
	// - **Items added:** 0
	// - **Bits set:** 0 (0.0% full)
	// - **Estimated false-positive rate:** 0.000%
	//
	// ## Recently added
	//
	// _Nothing added yet — call `Add` with an item string._
}
