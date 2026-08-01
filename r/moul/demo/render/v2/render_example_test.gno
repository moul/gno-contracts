package render

import "fmt"

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	fmt.Println(Render(""))
	// Output:
	// - [hello](/r/moul_basics_004:hello)
	// - [greetings/Manfred](/r/moul_basics_004:greetings/Manfred)
}
