package b58demo

// ExampleRender pins the realm's Render output as a gno testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Base58 (Bitcoin alphabet)
	//
	// Demo of the [`p/moul/x/daily/b58`](/p/moul/x/daily/b58/v1) library — base conversion from raw bytes (base-256) to base-58, using the Bitcoin alphabet (no `0`, `O`, `I`, `l`), pure byte-slice math, no `math/big`.
	//
	// ## Alphabet
	//
	// ```
	// 123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz
	// ```
	//
	// 58 characters, index 0…57.
	//
	// ## Examples
	//
	// | input (utf-8) | hex | Base58 |
	// |---|---|---|
	// | `(empty)` | `(empty)` | `` |
	// | `hello world` | `68656c6c6f20776f726c64` | `StV1DL6CwTryKyV` |
	// | `gno.land` | `676e6f2e6c616e64` | `JJR1f4BQc9H` |
	// | `Bitcoin` | `426974636f696e` | `3WyEDWjcVB` |
	//
	// Leading zero bytes → leading `1`s:
	//
	// | bytes | Base58 |
	// |---|---|
	// | `[0x00]` | `1` |
	// | `[0x00 0x00 0x00]` | `111` |
	//
	// ## Try it
	//
	// Append a hex string to the path to encode/round-trip it:
	//
	// - `/68656c6c6f` — the bytes for "hello"
	// - `/00000000` — four zero bytes
	// - `/deadbeef`
}
