package counter

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Counter Club
	//
	// A shared counter anyone can Inc, Dec, or Reset. The last 20 changes are logged below.
	//
	// ## Current value
	//
	// # 0
	//
	// **Total changes:** 0
	//
	// ## Recent history
	//
	// _No changes yet — be the first to count!_
}
