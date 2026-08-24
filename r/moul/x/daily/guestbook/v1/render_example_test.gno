package guestbook

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Guestbook
	//
	// _No one has signed yet. Be the first!_
}
