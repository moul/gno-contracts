package crowdfund

import "fmt"

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	fmt.Println(Render(""))
	// Output:
	// # Crowdfund
	//
	// No campaigns yet. Call `Launch(goal, durationBlocks)` to start one.
}
