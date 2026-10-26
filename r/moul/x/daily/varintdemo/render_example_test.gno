package varintdemo

// ExampleRender pins the realm's Render output as a testable example. The
// unsigned column is the protobuf base-128 vector set, so this doubles as a
// conformance test against the library.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Varint
	//
	// LEB128 base-128 integers, demoing the [`p/moul/x/daily/varint`](/p/moul/x/daily/varint/v0) library.
	//
	// ## Unsigned
	//
	// Seven payload bits per byte, so the length steps at every power of 128.
	//
	// | value | encoding | bytes |
	// | --- | --- | --- |
	// | `0` | `00` | 1 |
	// | `1` | `01` | 1 |
	// | `127` | `7f` | 1 |
	// | `128` | `80 01` | 2 |
	// | `300` | `ac 02` | 2 |
	// | `16383` | `ff 7f` | 2 |
	// | `16384` | `80 80 01` | 3 |
	// | `4294967296` | `80 80 80 80 10` | 5 |
	// | `18446744073709551615` | `ff ff ff ff ff ff ff ff ff 01` | 10 |
	//
	// ## Signed, through zigzag
	//
	// Encoding a negative directly would sign-extend it to ten bytes. Zigzag interleaves the signs first, so `-1` costs one byte and not ten.
	//
	// | value | zigzag | encoding | bytes |
	// | --- | --- | --- | --- |
	// | `0` | `0` | `00` | 1 |
	// | `-1` | `1` | `01` | 1 |
	// | `1` | `2` | `02` | 1 |
	// | `-64` | `127` | `7f` | 1 |
	// | `64` | `128` | `80 01` | 2 |
	// | `-9223372036854775808` | `18446744073709551615` | `ff ff ff ff ff ff ff ff ff 01` | 10 |
	// | `9223372036854775807` | `18446744073709551614` | `fe ff ff ff ff ff ff ff ff 01` | 10 |
	//
	// ## Only the canonical encoding decodes
	//
	// A padded varint means the same number has two spellings, which is a different hash for the same state. The decoder refuses them.
	//
	// | input | result |
	// | --- | --- |
	// | `80 00`, zero with one padding group | `varint: non-canonical encoding` |
	// | `81 00`, one with one padding group | `varint: non-canonical encoding` |
	// | `80`, continuation bit then nothing | `varint: truncated` |
	// | `ff ... ff 02`, ten groups, eleven bits too many | `varint: value overflows uint64` |
	//
	// > Try another value: append it to the path, for instance [`/-300`](/r/moul/x/daily/varintdemo/v0:/-300).
}

// ExampleRender_one pins the single-value path, and with it the escaping the
// realm owes a caller-supplied argument.
func ExampleRender_one() {
	print(Render("/-300"))
	// Output:
	// # Varint
	//
	// LEB128 base-128 integers, demoing the [`p/moul/x/daily/varint`](/p/moul/x/daily/varint/v0) library.
	//
	// ## `-300`
	//
	// - zigzag: `599`
	// - signed: `d7 04` (2 bytes)
}
