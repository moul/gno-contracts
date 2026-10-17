package bencodedemo

// ExampleRender pins the realm's Render output as a testable example. The
// refusal table is the library's strictness contract, so this doubles as a
// conformance test.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Bencode
	//
	// The BitTorrent serialization format, demoing the [`p/moul/x/daily/bencode`](/p/moul/x/daily/bencode/v0) library.
	//
	// ## The four types
	//
	// | encoding | kind | reads as |
	// | --- | --- | --- |
	// | `i42e` | int | 42 |
	// | `i-7e` | int | -7 |
	// | `4:spam` | string | spam |
	// | `0:` | string | _(empty string)_ |
	// | `li1ei2ei3ee` | list | 3 item(s) |
	// | `d3:cow3:moo4:spam4:eggse` | dict | 2 key(s): cow, spam |
	//
	// ## A torrent, decoded
	//
	// - dict, 2 key(s)
	//   - **announce**: string udp://tracker\.example
	//   - **info**:
	//     - dict, 3 key(s)
	//       - **length**: int `262144`
	//       - **name**: string disk\.img
	//       - **piece length**: int `16384`
	//
	// The `info` sub-dictionary re-encodes to `d6:lengthi262144e4:name8:disk.img12:piece lengthi16384ee`, 56 bytes. Hash those bytes and you have the infohash, which is why the decoder is not allowed to tidy anything up on the way through.
	//
	// ## What it refuses
	//
	// | input | why | error |
	// | --- | --- | --- |
	// | `i007e` | leading zeros in an integer | bencode: input is not canonical |
	// | `i-0e` | negative zero | bencode: input is not canonical |
	// | `03:abc` | leading zeros in a string length | bencode: input is not canonical |
	// | `d4:spam4:eggs3:cow3:mooe` | dictionary keys out of order | bencode: input is not canonical |
	// | `d3:cow3:moo3:cow3:mooe` | duplicate dictionary key | bencode: input is not canonical |
	// | `i1ei2e` | a second value after the first | bencode: trailing data after top-level value |
	//
	// > Every one of those parses. A decoder that accepted them and re-emitted the canonical form would change the identity of the document it was handed.
	//
	// Decode your own: [`d3:cow3:mooe`](/r/moul/x/daily/bencodedemo/v0:d3:cow3:mooe)
}

// ExampleRenderDecode pins the caller-supplied decode path: the tree, and the
// round trip that says the input was already canonical.
func ExampleRenderDecode() {
	print(Render("/d3:cowl1:ai7ee4:spam4:eggse"))
	// Output:
	// # Bencode
	//
	// The BitTorrent serialization format, demoing the [`p/moul/x/daily/bencode`](/p/moul/x/daily/bencode/v0) library.
	//
	// ## Your input
	//
	// d3:cowl1:ai7ee4:spam4:eggse
	//
	// - dict, 2 key(s)
	//   - **cow**:
	//     - list, 2 item(s)
	//       - string a
	//       - int `7`
	//   - **spam**: string eggs
	//
	// Re-encodes to d3:cowl1:ai7ee4:spam4:eggse, byte for byte.
	//
	// [back to the demo](/r/moul/x/daily/bencodedemo/v0)
}

// ExampleRenderReject pins what a non-canonical paste looks like.
func ExampleRenderReject() {
	print(Render("/i007e"))
	// Output:
	// # Bencode
	//
	// The BitTorrent serialization format, demoing the [`p/moul/x/daily/bencode`](/p/moul/x/daily/bencode/v0) library.
	//
	// ## Your input
	//
	// i007e
	//
	// Rejected: bencode: input is not canonical
	//
	// [back to the demo](/r/moul/x/daily/bencodedemo/v0)
}
