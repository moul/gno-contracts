package leaderboard

import "fmt"

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	fmt.Println(Render(""))
	// Output:
	// # 🏆 Leaderboard
	//
	// _No players yet. Call `AddPoints(n)` to get on the board._
}
