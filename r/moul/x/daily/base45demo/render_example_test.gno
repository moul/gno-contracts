package base45demo

// ExampleRender pins the realm's Render output as a testable example. The
// vector table is the RFC 9285 §4.4 set, so this doubles as a conformance
// test of the library underneath.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Base45
	//
	// The QR-alphanumeric encoding of RFC 9285, demoing the [`p/moul/x/daily/base45`](/p/moul/x/daily/base45/v0) library.
	//
	// ## The RFC 9285 vectors
	//
	// | input | base45 | characters |
	// | --- | --- | --- |
	// | _(empty)_ | _(empty)_ | 0 |
	// | `AB` | `BB8` | 3 |
	// | `ietf!` | `QED8WEX0` | 8 |
	// | `base-45` | `UJCLQE7W581` | 11 |
	// | `Hello!!` | `%69 VD92EX0` | 11 |
	//
	// ## Least significant character first
	//
	// Two bytes are one 16-bit number written in base 45, and the three characters come out in the order a human would call backwards. `AB` is `0x4142`, which is 16706:
	//
	// | place | digit | character |
	// | --- | --- | --- |
	// | 45^0 = 1 | 11 | `B` |
	// | 45^1 = 45 | 11 | `B` |
	// | 45^2 = 2025 | 8 | `8` |
	//
	// Read down the table and you get `BB8`, not `8BB`. An implementation that emits them the other way round still round-trips against itself, so only a published vector catches it.
	//
	// ## What the decoder refuses
	//
	// | string | verdict |
	// | --- | --- |
	// | `FGW` | accepted, 0xffff |
	// | `GGW` | rejected: base45: group out of range |
	// | `U5` | accepted, 0xff |
	// | `V5` | rejected: base45: group out of range |
	// | `B` | rejected: base45: corrupt input |
	// | `bb8` | rejected: base45: corrupt input |
	//
	// A group above `0xFFFF` is truncation waiting to happen, a length of 3n+1 is a character nobody wrote, and the alphabet is uppercase, so `bb8` is corrupt input rather than a case to fold.
	//
	// Pass a string of your own to encode it: `Render("/<text>")`.
}

// ExampleRenderArgument pins the encode-this-string path.
func ExampleRenderArgument() {
	print(Render("/gno.land"))
	// Output:
	// # Base45
	//
	// The QR-alphanumeric encoding of RFC 9285, demoing the [`p/moul/x/daily/base45`](/p/moul/x/daily/base45/v0) library.
	//
	// Encoding gno\.land:
	//
	// | field | value |
	// | --- | --- |
	// | input | 8 bytes |
	// | base45 | I3DM2EPVD0/D |
	// | characters | 12 |
}
