package importdemo

import "fmt"

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	fmt.Println(Render(""))
	// Output:
	// # [plot] Hello!
	//
	// ## Foo
	// foo foo foo
	// ## Bar
	// bar bar bar
}
