package facade

// ExampleRender pins what the facade renders before anything has registered.
// No implementation realm is imported here, so the facade stands alone.
func ExampleRender() {
	print(Render(""))
	// Output:
	// selfreg/facade/v0: no implementation registered
}
