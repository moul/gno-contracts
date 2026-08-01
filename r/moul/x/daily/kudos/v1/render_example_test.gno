package kudos

import "fmt"

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	fmt.Println(Render(""))
	// Output:
	// # Kudos
	//
	// Give props to addresses. `Give(to, reason)` records a kudos.
	//
	// ## Leaderboard
	//
	// _No kudos yet._
	//
	// ## Recent kudos
	//
	// _Nothing here yet._
}
