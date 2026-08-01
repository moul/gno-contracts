package cowsaydemo

import "fmt"

// ExampleRender pins the realm's Render output as a gno testable example.
func ExampleRender() {
	fmt.Println(Render(""))
	// Output:
	// # cowsay
	//
	// _Tip: pass a message in the path, e.g._ `/Hello, gno.land!`
	//
	// ```
	//  ______
	// < Moo! >
	//  ------
	//         \   ^__^
	//          \  (oo)\_______
	//             (__)\       )\/\
	//                 ||----w |
	//                 ||     ||
	// ```
}
