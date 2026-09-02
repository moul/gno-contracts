package crc32demo

// ExampleRender pins the realm's root Render output as a testable example.
// The `123456789` row is the standard CRC-32 check value, so this example
// doubles as a conformance test for the library.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # CRC-32
	//
	// The IEEE checksum behind zip, gzip and PNG, demoing the [`p/moul/x/daily/crc32`](/p/moul/x/daily/crc32/v1) library.
	//
	// | input | crc32 |
	// |---|---|
	// | _(empty)_ | `00000000` |
	// | `a` | `e8b7be43` |
	// | `abc` | `352441c2` |
	// | `123456789` | `cbf43926` |
	// | `hello world` | `0d4a1185` |
	// | `hello worle` | `7a4d2113` |
	//
	// `123456789` → `cbf43926` is the standard CRC-32 check value, so this table doubles as a conformance test.
	//
	// > The last two rows differ by one letter and share no digits: that avalanche is the point.
	//
	// > A CRC detects **accidents**, not tampering — it is linear, so a matching message is easy to craft. Never authenticate with it.
}
