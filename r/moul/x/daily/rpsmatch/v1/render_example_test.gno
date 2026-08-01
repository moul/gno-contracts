package rpsmatch

import "fmt"

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	fmt.Println(Render(""))
	// Output:
	// # Rock-Paper-Scissors Arena
	//
	// Best-of-three matches against the house. First to 2 round wins takes the match.
	//
	// - Total rounds played: 0
	// - No champion yet — be the first to win a match.
	//
	// ## How to play
	//
	// Call `Throw("rock"|"paper"|"scissors")` (or `r`/`p`/`s`). Your throw starts a new match if you don't have one in progress, and each call plays one round of it.
	//
	// View your own record at this realm's path plus your address, e.g. `.../rpsmatch:g1youraddress...`
}
