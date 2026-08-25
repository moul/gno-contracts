package rpsoracle

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Rock-Paper-Scissors Oracle
	//
	// An adaptive opponent: it doesn't roll dice, it studies you. Every throw is logged, and the oracle always counters whichever move you've played most often. Play a uniform mixed strategy and it can't out-guess you; fall into a habit and it will.
	//
	// - Total rounds played: 0
	// - No one has beaten the oracle yet.
	//
	// ## How to play
	//
	// Call `Play("rock"|"paper"|"scissors")` (or `r`/`p`/`s`). View your own record at this realm's path plus your address, e.g. `.../rpsoracle:g1youraddress...`
}
