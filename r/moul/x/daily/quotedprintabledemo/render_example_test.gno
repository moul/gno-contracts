package quotedprintabledemo

// ExampleRender pins the realm's Render output as a testable example. The two
// encoding columns are produced by the library, so this doubles as a
// conformance test for both rulesets at once.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Quoted-Printable
	//
	// RFC 2045 bodies and RFC 2047 header words, demoing the [`p/moul/x/daily/quotedprintable`](/p/moul/x/daily/quotedprintable/v0) library.
	//
	// ## The same bytes, two rulesets
	//
	// | input | body (RFC 2045) | header word (RFC 2047) |
	// | --- | --- | --- |
	// | `hello world` | `hello world` | `=?UTF-8?Q?hello_world?=` |
	// | `café` | `caf=C3=A9` | `=?UTF-8?Q?caf=C3=A9?=` |
	// | `a=b` | `a=3Db` | `=?UTF-8?Q?a=3Db?=` |
	// | `why not?` | `why not?` | `=?UTF-8?Q?why_not=3F?=` |
	// | ` trailing space  ` | `trailing space=20` | `=?UTF-8?Q?trailing_space_?=` |
	// | `two\r\nlines` | `two=0D=0Alines` | `=?UTF-8?Q?two=0D=0Alines?=` |
	//
	// > A body leaves a space and a `?` alone; a header word cannot, because a header is parsed into tokens before anything looks at the text. That is why the space becomes `_` and the `?` becomes `=3F`. Encoding a subject line with the body codec is the classic bug: it looks encoded, and the receiving parser stops at the first `?`.
	//
	// ## Soft breaks at 76 columns
	//
	// 300 literal characters, wrapped by the encoder:
	//
	// - `gnognognognognognognognognognognognognognognognognognognognognognognognogno=` (76)
	// - `gnognognognognognognognognognognognognognognognognognognognognognognognogno=` (76)
	// - `gnognognognognognognognognognognognognognognognognognognognognognognognogno=` (76)
	// - `gnognognognognognognognognognognognognognognognognognognognognognognognogno` (75)
	//
	// > The trailing `=` is the soft break: it says the line was wrapped by the encoder and is not a line of the data. 76 columns is the RFC's hard limit and the `=` counts toward it, so the content stops at 75.
	//
	// ## Every byte survives
	//
	// `a\r\nb` encodes to `a=0D=0Ab` and decodes back unchanged ✅
	//
	// > CR and LF are encoded as data rather than written out as line structure. A realm encodes a payload, not a mail message, and an encoder that normalised line endings on the way through would quietly break a signature.
}
