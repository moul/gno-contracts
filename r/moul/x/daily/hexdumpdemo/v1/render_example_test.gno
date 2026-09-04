package hexdumpdemo

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Hexdump
	//
	// Bytes in the classic `xxd -C` layout, demoing the [`p/moul/x/daily/hexdump`](/p/moul/x/daily/hexdump/v1) library.
	//
	// ## A plain string
	//
	// ```
	// 00000000  48 65 6c 6c 6f 2c 20 67  6e 6f 2e 6c 61 6e 64 21  |Hello, gno.land!|
	// ```
	//
	// _`Hello, gno.land!` → 16 bytes._
	//
	// ## Alignment on a partial line
	//
	// The last line is short, so the hex columns are padded and the ASCII gutter stays put — that alignment is the whole point of the layout.
	//
	// ```
	// 00000000  30 31 32 33 34 35 36 37  38 39 61 62 63 64 65 66  |0123456789abcdef|
	// 00000010  68 69                                             |hi|
	// ```
	//
	// _`0123456789abcdefhi` → 18 bytes._
	//
	// ## What a rendered string hides
	//
	// These two look identical in any UI:
	//
	// - `"hi"`
	// - `"hi "` — one trailing space
	//
	// ```
	// 00000000  68 69                                             |hi|
	// ```
	//
	// _`hi` → 2 bytes._
	//
	// ```
	// 00000000  68 69 20                                          |hi |
	// ```
	//
	// _`hi ` → 3 bytes._
	//
	// ## Multi-byte UTF-8
	//
	// `"café"` is 5 bytes, not 4: `é` is `c3 a9`. Non-printables render as `.`.
	//
	// ```
	// 00000000  63 61 66 c3 a9                                    |caf..|
	// ```
	//
	// _`café` → 5 bytes._
	//
	// ## Control characters
	//
	// A NUL, a newline and a tab are invisible in text and obvious here.
	//
	// ```
	// 00000000  00 0a 09 6f 6b                                    |...ok|
	// ```
	//
	// _5 bytes._
}
