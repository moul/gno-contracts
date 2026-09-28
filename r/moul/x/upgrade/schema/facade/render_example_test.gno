package facade

// ExampleRender pins the facade before any handler realm exists. Nothing is
// imported here, so there is no candidate and nothing accepted.
func ExampleRender() {
	print(Render(""))
	// Output:
	// schema/facade/v0: no handler accepted (0 candidate(s))
}
