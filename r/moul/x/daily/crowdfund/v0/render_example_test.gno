package crowdfund

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Crowdfund
	//
	// No campaigns yet. Call `Launch(goal, durationBlocks)` to start one.
}
