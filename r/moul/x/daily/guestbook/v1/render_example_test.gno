package guestbook

import "fmt"

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	fmt.Println(Render(""))
	// Output:
	// # Guestbook
	//
	// _No one has signed yet. Be the first!_
}
