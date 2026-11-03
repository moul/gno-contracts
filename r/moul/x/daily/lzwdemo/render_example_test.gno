package lzwdemo

// ExampleRender pins the realm's Render output as a testable example. Every
// figure in it is derived from the fixed strings in lzwdemo.gno, so a change
// in the library's code stream, widths or bit counts fails here.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # LZW
	//
	// Dictionary compression, demoing the [`p/moul/x/daily/lzw`](/p/moul/x/daily/lzw/v0) library. Both sides start from the same 256 entries, one per byte, and both add the same entry after every code, so the dictionary is never sent: the payload is nothing but a stream of codes.
	//
	// ## `mississippi`
	//
	// | # | code | means | decoder adds |
	// | --- | --- | --- | --- |
	// | 1 | 109 | `m` |  |
	// | 2 | 105 | `i` | 256 = `mi` |
	// | 3 | 115 | `s` | 257 = `is` |
	// | 4 | 115 | `s` | 258 = `ss` |
	// | 5 | 257 | `is` | 259 = `si` |
	// | 6 | 259 | `si` | 260 = `iss` |
	// | 7 | 112 | `p` | 261 = `sip` |
	// | 8 | 112 | `p` | 262 = `pp` |
	// | 9 | 105 | `i` |  |
	//
	// A code under 256 is a byte. Anything above it names a string an earlier step added. The last column is the DECODER's table, which runs one entry behind the encoder's: the encoder added `mi` while emitting step 1, the decoder cannot add it until it has read step 2, and step 9 adds nothing because the stream ends. 81 bits against 88 raw, 7 saved (7%).
	//
	// `Decode()` returns `mississippi`, the input it started from. ✅
	//
	// ## The decoder is one entry behind
	//
	// The encoder can emit a code on the same step that creates it, and the decoder then meets a code its table does not hold. It happens on any run of a repeating pattern, and `aaaaa` is the shortest input that does it:
	//
	// | # | code | means | in the table yet? |
	// | --- | --- | --- | --- |
	// | 1 | 97 | `a` | yes |
	// | 2 | 256 | `aa` | **no, synthesised** |
	// | 3 | 256 | `aa` | yes |
	//
	// The entry cannot be anything but the previous one with its own first byte appended, because that is the only string the encoder could have built there. A decoder that only looks codes up returns an error on five bytes of `a`.
	//
	// ## What repetition is worth
	//
	// | input | codes | raw | coded | saved |
	// | --- | --- | --- | --- | --- |
	// | `abcdefgh` | 8 | 64 bits | 72 bits | -12% |
	// | `the quick brown fox jumps over the lazy dog` | 41 | 344 bits | 369 bits | -7% |
	// | `mississippi` | 9 | 88 bits | 81 bits | 7% |
	// | `abababababababababababababababab` | 11 | 256 bits | 99 bits | 61% |
	//
	// Short and unrepeating loses: nine-bit codes standing in for eight-bit bytes cost an eighth more, and LZW has nothing to sell until a string comes back a second time. That is the opposite trade from Huffman, which pays for a table up front and then wins on skew rather than on repetition.
	//
	// ## The code width grows with the dictionary
	//
	// Codes start at nine bits and widen as the table fills. The encoder widens after adding the entry that filled the old width; the decoder has added one fewer by then, so it has to widen one entry early or every later code comes out shifted by a bit. That does not fail, it returns a different string, which is why it is the bug LZW is known for.
	//
	// | width | first code at it | dictionary size there |
	// | --- | --- | --- |
	// | 9 bits | #1 | 256 |
	// | 10 bits | #257 | 512 |
	//
	// Measured on 768 bytes that repeat little: 512 codes, 4864 bits. The next two steps are at code 769 and code 1793, and then the table freezes at 12 bits: this coder has no reset code, so a stream has exactly one reading.
	//
	// ## Try your own
	//
	// ```
	// /r/moul/x/daily/lzwdemo/v0:mississippi
	// ```
}

// ExampleRender_input pins the caller-supplied path, which is the only part of
// the page that is not fixed.
func ExampleRender_input() {
	print(Render("/banana"))
	// Output:
	// # LZW
	//
	// Input: `banana`
	//
	// | # | code | bits | means |
	// | --- | --- | --- | --- |
	// | 1 | 98 | 9 | b |
	// | 2 | 97 | 9 | a |
	// | 3 | 110 | 9 | n |
	// | 4 | 257 | 9 | an |
	// | 5 | 97 | 9 | a |
	//
	// 45 bits against 48 raw, 3 saved (6%).
	//
	// [back](/r/moul/x/daily/lzwdemo/v0)
}

// ExampleRender_pipe is the regression for the one way a caller's string can
// still rewrite this page: a pipe ends a table cell from inside a code span,
// so the entry column goes through ui.Cell and not md.InlineCode. Before the
// fix this row had five cells under a four-column header.
func ExampleRender_pipe() {
	print(Render("/a|b|c"))
	// Output:
	// # LZW
	//
	// Input: `a|b|c`
	//
	// | # | code | bits | means |
	// | --- | --- | --- | --- |
	// | 1 | 97 | 9 | a |
	// | 2 | 124 | 9 | \| |
	// | 3 | 98 | 9 | b |
	// | 4 | 124 | 9 | \| |
	// | 5 | 99 | 9 | c |
	//
	// 45 bits against 40 raw, -5 saved (-12%).
	//
	// [back](/r/moul/x/daily/lzwdemo/v0)
}
