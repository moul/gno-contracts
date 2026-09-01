package disjointsetdemo

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Union-Find
	//
	// Disjoint-set forest with path compression and union by rank, demoing the [`p/moul/x/daily/disjointset`](/p/moul/x/daily/disjointset/v1) library.
	//
	// ## Merges applied
	//
	// - `Union(0, 1)`
	// - `Union(2, 3)`
	// - `Union(1, 3)`
	// - `Union(5, 6)`
	// - `Union(7, 8)`
	// - `Union(8, 9)`
	//
	// ## Partition of [0, 10)
	//
	// **4** groups:
	//
	// - `{0, 1, 2, 3}`
	// - `{4}`
	// - `{5, 6}`
	// - `{7, 8, 9}`
	//
	// > Groups come out sorted, ordered by their smallest member, so the partition is identical whatever order the merges arrive in.
}
