package memory

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # 🧠 Memory Match
	//
	// Match all 8 emoji pairs on the 4x4 grid.
	//
	// | | | | |
	// |:-:|:-:|:-:|:-:|
	// | ❓ | ❓ | ❓ | ❓ |
	// | ❓ | ❓ | ❓ | ❓ |
	// | ❓ | ❓ | ❓ | ❓ |
	// | ❓ | ❓ | ❓ | ❓ |
	//
	// - Moves: **0**
	// - Pairs matched: **0 / 8**
	// - Seed height: **123**
	//
	// Call `Flip(index)` with a cell index 0–15. `NewGame()` reshuffles.
}
