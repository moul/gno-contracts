package cowsaydemo

// ExampleRender pins the realm's Render output as a gno testable example.
func ExampleRender() {
	print(Render(""))
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
