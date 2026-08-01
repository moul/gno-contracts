package governor

import "fmt"

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	fmt.Println(Render(""))
	// Output:
	// # 🏛️ Governor
	//
	// Simplified on-chain governance — 1 address = 1 vote, voting period of 100 blocks.
	//
	// Current chain height: **123**
	//
	// _No proposals yet. Call `Propose` to create one._
}
