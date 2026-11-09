package cobsdemo

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # COBS
	//
	// Consistent Overhead Byte Stuffing, demoing the [`p/moul/x/daily/cobs`](/p/moul/x/daily/cobs/v0) library.
	//
	// ## A frame, byte for byte
	//
	// Each group is a code byte then up to 254 non-zero bytes. The code is the group length plus one, and a group under the maximum ends in a zero the frame does not store.
	//
	// | payload | frame | bytes |
	// | --- | --- | --- |
	// | the empty payload `(none)` | `01` | 0 to 1 |
	// | one zero `00` | `01 01` | 1 to 2 |
	// | two zeros `00 00` | `01 01 01` | 2 to 3 |
	// | a zero in the middle `11 22 00 33` | `03 11 22 02 33` | 4 to 5 |
	// | no zero at all `11 22 33 44` | `05 11 22 33 44` | 4 to 5 |
	// | three trailing zeros `11 00 00 00` | `02 11 01 01 01` | 4 to 5 |
	//
	// ## The payload an escaper fears is the cheap one here
	//
	// Escaping every zero doubles an all-zero payload. COBS stores the distances between zeros instead, so an all-zero payload costs exactly one byte, at any length, and the expensive direction is the one with no zeros in it at all.
	//
	// | payload bytes | all zeros | no zeros | escaping, worst case |
	// | --- | --- | --- | --- |
	// | 1 | +1 | +1 | +1 |
	// | 254 | +1 | +1 | +254 |
	// | 255 | +1 | +2 | +255 |
	// | 509 | +1 | +3 | +509 |
	// | 1000 | +1 | +4 | +1000 |
	//
	// ## Packing records into one string
	//
	// The reason to remove the zeros: every boundary can then be found by scanning for one, with no length table and no parsing.
	//
	// | record | frame |
	// | --- | --- |
	// | `61 6c 69 63 65` | `06 61 6c 69 63 65 00` |
	// | `00 00` | `01 01 01 00` |
	// | `61 00 62` | `02 61 02 62 00` |
	// | `(none)` | `01 00` |
	// | `62 6f 62` | `04 62 6f 62 00` |
	//
	// Packed, the five records are 23 bytes carrying 13 of payload:
	//
	// ```
	// 06 61 6c 69 63 65 00 01 01 01 00 02 61 02 62 00 01 00 04 62 6f 62 00
	// ```
	//
	// and `Unpack` gives back 5 records, the empty one included.
	//
	// ## What the decoder refuses
	//
	// A frame is checked, never repaired: a short payload looks exactly like a complete one, and a payload with two frames is two hashes for one piece of state.
	//
	// | frame | result |
	// | --- | --- |
	// | a zero inside the frame | `cobs: zero byte inside a frame` |
	// | a code byte promising 4 bytes, 2 given | `cobs: frame ends inside a group` |
	// | nothing at all | `cobs: empty frame` |
	// | a full group padded with an empty one | `cobs: non-canonical encoding` |
	//
	// > Frame your own text: append it to the path, for instance [`/hello`](/r/moul/x/daily/cobsdemo/v0:/hello).
}
