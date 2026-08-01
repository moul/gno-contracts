package gnoface

import "fmt"

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	fmt.Println(Render(""))
	// Output:
	// Gnoface #653437485
	// ```
	//    s s s
	//  /|||||||\
	//  |       |
	//  | .   . |
	// O| o   o |o
	//  |       |
	//  |   ~   |
	//  |       |
	//  |   .   |
	//  |       |
	//  \~~~~~~~/
	// ```
}
