package logic

// ExampleRender pins the render of the logic realm against an untouched store.
func ExampleRender() {
	print(Render(""))
	// Output:
	// store/logic/v0: counter=0 step=1
}
