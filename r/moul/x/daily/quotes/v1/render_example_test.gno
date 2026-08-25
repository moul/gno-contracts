package quotes

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Quote of the Moment
	//
	// > He who is brave is free.
	// >
	// > — the board (#3)
	//
	// _Featured pick rotates with block height 123 — index 3 of 4._
	//
	// ## All quotes (4)
	//
	// - **#0** The unexamined life is not worth living. — _the board_
	// - **#1** We suffer more often in imagination than in reality. — _the board_
	// - **#2** Waste no more time arguing about what a good person should be. Be one. — _the board_
	// - **#3** He who is brave is free. — _the board_
}
