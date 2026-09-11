package lottery

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Lottery
	//
	// Enter the open round, then anyone can draw once it has at least two players. The winner is picked from the block height and a new round opens automatically.
	//
	// ## Round 1 (open)
	//
	// _No entrants yet. Call `Enter` to join._
	//
	// ## Past winners
	//
	// _No rounds drawn yet._
}
