package hmacdemo

// ExampleRender pins the realm's root Render output as a testable example.
// The "matches" column is computed from the library against RFC 4231's
// published tags, so this example is also a conformance test: a change that
// broke HMAC would flip a cell to "no" here before it reached a chain.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # HMAC-SHA-256
	//
	// Keyed message authentication, demoing the [`p/moul/x/daily/hmac`](/p/moul/x/daily/hmac/v0) library. Every tag below is computed while this page renders.
	//
	// ## RFC 4231, checked here
	//
	// | case | key | message | tag | matches |
	// | --- | --- | --- | --- | --- |
	// | 1 | 20 bytes | 8 bytes | `b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7` | yes |
	// | 2 | 4 bytes | 28 bytes | `5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843` | yes |
	// | 3 | 20 bytes | 50 bytes | `773ea91e36800e46854db8ebd09181a72959098b3ef8c122d9635514ced565fe` | yes |
	// | 6 | 131 bytes | 54 bytes | `60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54` | yes |
	// | 7 | 131 bytes | 152 bytes | `9b09ffa71b942fcb27635fbcd5b0e944bfdc63644f0713938a7f51535c3a35e2` | yes |
	//
	// Every row has to say yes. One saying no means this chain is serving a library that is not HMAC.
	//
	// ## Two different keys, one tag
	//
	// | key | bytes | tag |
	// | --- | --- | --- |
	// | 131 copies of `0xaa` | 131 | `f7cc137015898c0e3b1a06b1164895fb91d62ba0e12f8c5972c3a39e135319ae` |
	// | its SHA-256 | 32 | `f7cc137015898c0e3b1a06b1164895fb91d62ba0e12f8c5972c3a39e135319ae` |
	//
	// A key longer than the 64-byte block is replaced by its own digest before use, so those two keys are the same key. Equal: **yes**. The mirror of this rule is that a short key is zero-padded, so `moul` and `moul` followed by zeros are also one key. Pick keys of exactly 32 random bytes and neither collision class can reach you.
	//
	// ## Why not sha256(key + message)
	//
	// | construction | tag |
	// | --- | --- |
	// | `hmac(key, message)` | `185144fe6ab8ff4ee0118a1441c2d7911a80f07607ec968a2abee25c2df6e7c1` |
	// | `sha256(key + message)` | `c8af45c152186266cc24b0285bc5d00c05a90c39058b807db308369c4740b5b6` |
	//
	// Both are 32 bytes and both change when either input changes, which is why the second one gets written. It is not a MAC: SHA-256 publishes its internal state as its output, so a holder of one valid tag can append to the message and produce a valid tag for the longer message without ever learning the key. HMAC hashes twice and the extensible digest never leaves the function.
	//
	// ## Tag your own
	//
	// Append any text to the path to tag it under the key `moul`, which is written here in public because a realm cannot hold a secret:
	//
	// [`/gno.land`](/r/moul/x/daily/hmacdemo/v0:/gno.land) or any other text.
}
