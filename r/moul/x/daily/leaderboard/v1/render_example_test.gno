package leaderboard

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # 🏆 Leaderboard
	//
	// _No players yet. Call `AddPoints(n)` to get on the board._
}
