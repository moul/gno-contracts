package importdemo

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # [thread] Hello!
	//
	// ## Foo
	// foo foo foo
	// ## Bar
	// bar bar bar
}
