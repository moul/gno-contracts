package ascii85demo

// ExampleRender pins the realm's Render output as a testable example. The
// ascii85 column doubles as a conformance check: every value is what Go's
// encoding/ascii85 produces for the same input.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # ascii85
	//
	// Four bytes into five printable characters, demoing the [`p/moul/x/daily/ascii85`](/p/moul/x/daily/ascii85/v0) library.
	//
	// ## What it costs
	//
	// | input | bytes | ascii85 | characters |
	// | --- | --- | --- | --- |
	// | _(empty)_ | 0 | _(empty)_ | 0 |
	// | `s` | 1 | `Er` | 2 |
	// | `su` | 2 | `F*.` | 3 |
	// | `sur` | 3 | `F*2L` | 4 |
	// | `sure` | 4 | `F*2M7` | 5 |
	// | `sure.` | 5 | `F*2M7/c` | 7 |
	// | ` Man  ` | 4 | `9jqo^` | 5 |
	// | `gno.land` | 8 | `B5VW?Cgh3l` | 10 |
	//
	// Five characters per four bytes is 25% expansion, against 33% for base64 and 100% for hex. Encoding 400 bytes gives 500 characters where base64 would give 536 and hex 800. You pay for it with an alphabet that is neither URL-safe nor case-insensitive, which is why base64 kept the web and ascii85 kept PostScript.
	//
	// ## The zero shortcut
	//
	// Four zero bytes are written as the single character `z`, so the output is not a fixed ratio of the input: a run of zeroes costs a fifth of what the arithmetic says.
	//
	// It only fires on a group boundary, which is the part that surprises:
	//
	// - `abcd` + four zeroes + `efgh` becomes `@:E_WzAS,Rg`
	// - `abc` + the same four zeroes + `def` becomes `@:E^H!!!"0AS(`
	//
	// The same four bytes, one character in the first and five in the second, because in the second they are split across two groups and neither is all zero. Decoding rejects a `z` that appears once a group has been started, for the same reason.
	//
	// ## What it refuses
	//
	// A five-character group is a base-85 numeral, and only values below 2^32 name four bytes. Nothing in the alphabet stops a stream from spelling a larger one, and Go's `encoding/ascii85` holds the group in a `uint32` and lets it wrap:
	//
	// | group | names | here |
	// | --- | --- | --- |
	// | `s8W-"` | 2^32 or more | refused: `ascii85: group overflows 32 bits` |
	// | `uuuuu` | 2^32 or more | refused: `ascii85: group overflows 32 bits` |
	// | `s8W-#` | 2^32 or more | refused: `ascii85: group overflows 32 bits` |
	// | `s8W-!` | 2^32 - 1 | 4 bytes, all `0xFF` |
	//
	// > Two different texts decoding to the same bytes is a forgery primitive wherever the text is what gets signed, compared or used as a key. `s8W-"` is 2^32 exactly, and in Go it decodes to the same four zero bytes as the one-character shortcut.
}

// ExampleRender_text pins the per-input page, including the framed form.
func ExampleRender_text() {
	print(Render("/gno.land"))
	// Output:
	// # ascii85
	//
	// Four bytes into five printable characters, demoing the [`p/moul/x/daily/ascii85`](/p/moul/x/daily/ascii85/v0) library.
	//
	// ## gno\.land
	//
	// | form | output |
	// | --- | --- |
	// | bare | `B5VW?Cgh3l` |
	// | framed | `<~B5VW?Cgh3l~>` |
	// | bytes in | 8 |
	// | characters out | 10 |
	// | round trip | exact ✅ |
	//
	// > The framed form is what a PostScript or PDF stream carries. `Decode` takes either, and ignores the line breaks an encoder inserts.
}
