package lazy

// ExampleRender pins the render of the seeded v0 store.
func ExampleRender() {
	print(Render(""))
	// Output:
	// lazy/v0: 2 records
	// - ada: v0{ada 1}
	// - bob: v0{bob 2}
}
