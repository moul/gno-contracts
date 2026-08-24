package rot13demo

// ExampleRender pins the realm's Render output as a gno testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # ROT13
	//
	// Demo of the [`p/moul/x/daily/rot13`](/p/moul/x/daily/rot13/v1) library — an on-chain port of Go's classic **ROT13** cipher, the standard-library `strings.Map` / `io.Reader` teaching example. Each ASCII letter is rotated 13 places through the alphabet; everything else is left alone.
	//
	// Because the alphabet has 26 letters and 13 is exactly half, **ROT13 is its own inverse** — encoding twice returns the original text.
	//
	// ## Example
	//
	// | stage | text |
	// |---|---|
	// | input | `Hello, Gno!` |
	// | ROT13 | `Uryyb, Tab!` |
	// | ROT13 again | `Hello, Gno!` |
	//
	// ## Try it
	//
	// - `Render("/Uryyb, Tab!")` — decode any text (append it to the path).
	// - `Render("/caesar/3/attack at dawn")` — a general Caesar shift.
	//
	// Or call the library functions directly:
	//
	// ```go
	// rot13.Rot13("Hello, Gno!")     // "Uryyb, Tab!"
	// rot13.Caesar("attack", 3)      // "dwwdfn"
	// rot13.Caesar("Hello", 13)      // same as Rot13: "Uryyb"
	// ```
}
