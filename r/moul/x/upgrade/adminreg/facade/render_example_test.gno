package facade

// ExampleRender pins the facade before any implementation realm exists. Nothing
// is imported here, so there is no candidate and nothing accepted.
func ExampleRender() {
	print(Render(""))
	// Output:
	// adminreg/facade/v0
	// live: none accepted
	// candidates: 0
}
