package home

// ExampleRender pins the assembled page. It seeds state directly (rather than
// through Set) so the example takes no `cur realm`, and it uses only
// non-volatile placeholders so the golden output does not depend on the test
// machine's block height or chain id.
func ExampleRender() {
	reset()
	seed("layout", "# :owner:\n\n:bio:\n\n## Packages\n\n:packages:\n")
	seed("bio", "Building on gno.")
	seed("packages", "- p/moul/dynreplacer\n- r/moul/home")
	print(Render(""))
	// Output:
	// # g1manfred47kzduec920z88wfr64ylksmdcedlf5
	//
	// Building on gno.
	//
	// ## Packages
	//
	// - p/moul/dynreplacer
	// - r/moul/home
}
