package timelock

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Timelock Controller
	//
	// Current chain height: **123**
	//
	// _No operations scheduled yet._
	//
	// Call `Schedule(action, delayBlocks)` to queue one.
}
