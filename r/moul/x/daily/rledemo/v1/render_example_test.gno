package rledemo

// ExampleRender pins the realm's root Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Run-Length Encoding
	//
	// `<count><char>` pairs, demoing the [`p/moul/x/daily/rle`](/p/moul/x/daily/rle/v1) library.
	//
	// | input | encoded | size | round-trips |
	// |---|---|---|---|
	// | `aaaaaaaaaabbbbbbbbbb` | `10a10b` | 30% | ✅ |
	// | `aaabbc` | `3a2b1c` | 100% | ✅ |
	// | `abcdef` | `1a1b1c1d1e1f` | 200% | ✅ |
	//
	// > Over 100% means the encoding made the data **bigger**. RLE only wins on runny input, and `abcdef` is the honest counter-example.
	//
	// > Append text to the path to encode it — digits are rejected, since they would be ambiguous with a run count.
}

// ExampleRender_rejectsDigits pins the refusal path: digits cannot be encoded
// because they are indistinguishable from a run count on the way back.
func ExampleRender_rejectsDigits() {
	print(Render("/ab3c"))
	// Output:
	// # Run-Length Encoding
	//
	// `<count><char>` pairs, demoing the [`p/moul/x/daily/rle`](/p/moul/x/daily/rle/v1) library.
	//
	// ## `ab3c`
	//
	// _rle: input must not contain digits_
}
