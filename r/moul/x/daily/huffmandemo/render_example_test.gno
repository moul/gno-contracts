package huffmandemo

// ExampleRender pins the realm's Render output as a testable example. Every
// figure in it is derived from the fixed strings in huffmandemo.gno, so a
// change in the library's table or bit count fails here.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Huffman coding
	//
	// Frequency-based prefix codes, demoing the [`p/moul/x/daily/huffman`](/p/moul/x/daily/huffman/v0) library. Rare symbols get long codes, common ones get short codes, and no code is a prefix of another, so the stream needs no separators.
	//
	// ## `abracadabra`
	//
	// | symbol | count | code | bits |
	// | --- | --- | --- | --- |
	// | `a` | 5 | `0` | 1 |
	// | `b` | 2 | `100` | 3 |
	// | `c` | 1 | `101` | 3 |
	// | `d` | 1 | `110` | 3 |
	// | `r` | 2 | `111` | 3 |
	//
	// The table is sorted by (length, symbol) and the codes are assigned from the lengths alone. That is what canonical means: the decoder rebuilds every code from one small integer per symbol, and two runs over the same input can never disagree about the table.
	//
	// ### The stream
	//
	// ```
	// 01001110101011001001110
	// ```
	//
	// 23 bits against 88 raw, 65 saved (73%).
	//
	// `Decode()` returns `abracadabra`, the input it started from. ✅
	//
	// ## What the skew is worth
	//
	// | input | symbols | raw | coded | saved |
	// | --- | --- | --- | --- | --- |
	// | `abcdefgh` | 8 | 64 bits | 24 bits | 62% |
	// | `the quick brown fox jumps over the lazy dog` | 27 | 344 bits | 192 bits | 44% |
	// | `mississippi` | 4 | 88 bits | 21 bits | 76% |
	// | `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaabcd` | 4 | 264 bits | 38 bits | 85% |
	//
	// The floor is the alphabet, not the algorithm: eight distinct bytes used once each cost three bits apiece, which is what a fixed-width code over eight symbols would have spent anyway. Everything past that floor is bought with skew.
	//
	// ## The two inputs that break a naive implementation
	//
	// **One distinct symbol.** Its leaf has no sibling, so the tree walk gives it a zero-bit code and the stream comes out empty: here `aaaaa` is `00000`, five one-bit codes, and it is the only incomplete code the library emits.
	//
	// **A payload that was edited.** `Decode` rebuilds the canonical table from the lengths it was handed and refuses a payload whose own bits disagree with it, so a stored `Encoded` cannot be bent into decoding as a different string:
	//
	// ```
	// huffman: corrupt payload
	// ```
	//
	// ## Try your own
	//
	// ```
	// /r/moul/x/daily/huffmandemo/v0:mississippi
	// ```
}

// ExampleRender_input pins the caller-supplied path, which is the only part of
// the page that is not fixed.
func ExampleRender_input() {
	print(Render("/hello"))
	// Output:
	// # Huffman coding
	//
	// Input: `hello`
	//
	// | symbol | count | code | bits |
	// | --- | --- | --- | --- |
	// | `e` | 1 | `00` | 2 |
	// | `h` | 1 | `01` | 2 |
	// | `l` | 2 | `10` | 2 |
	// | `o` | 1 | `11` | 2 |
	//
	// 10 bits against 40 raw, 30 saved (75%).
	//
	// [back](/r/moul/x/daily/huffmandemo/v0)
}
