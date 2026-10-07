package b58demo

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// ExampleRender pins the realm's Render output as a gno testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Base58 (Bitcoin alphabet)
	//
	// Demo of the [`p/moul/x/daily/b58`](/p/moul/x/daily/b58/v0) library — base conversion from raw bytes (base-256) to base-58, using the Bitcoin alphabet (no `0`, `O`, `I`, `l`), pure byte-slice math, no `math/big`.
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

// The invalid-hex branch puts the visitor's raw URL path into a code span, and
// ANY non-hex path reaches it. Building that span by hand let a backtick in the
// path close it early, so the rest of the path rendered as markdown on a
// gno.land page: a crafted link produced attacker-authored headings and links.
// Measured through goldmark v1.8.2 with gnoweb's extension set.
func TestInvalidHexPathCannotEscapeItsCodeSpan(t *testing.T) {
	out := Render("/zz")
	uassert.True(t, strings.Contains(out, "`zz`"),
		"a plain invalid path is not shown verbatim in a code span")

	// One backtick in the path must widen the fence, not close the span.
	out = Render("/a`b")
	uassert.True(t, strings.Contains(out, "``a`b``"),
		"the fence does not outscan the caller's backtick, so the span closes early")

	// The markdown that follows a closing backtick must stay inert.
	out = Render("/x` and [CLICK](https://evil.example) `")
	uassert.False(t, strings.Contains(out, "] and [CLICK]"),
		"caller markdown escaped the code span")
	uassert.True(t, strings.Contains(out, "is not a valid hex string"),
		"the realm's own sentence did not survive")
}
