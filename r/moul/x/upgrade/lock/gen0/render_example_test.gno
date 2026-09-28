package lock

// ExampleRender pins the render of a freshly deployed, still-live version.
func ExampleRender() {
	print(Render(""))
	// Output:
	// lock/v0: 0 (live)
}
