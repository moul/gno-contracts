package punycodedemo

// ExampleRender pins the realm's Render output as a testable example. Four of
// the label rows are RFC 3492 section 7.1 vectors, so this doubles as a
// conformance test.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Punycode
	//
	// RFC 3492 bootstring, demoing the [`p/moul/x/daily/punycode`](/p/moul/x/daily/punycode/v0) library.
	//
	// | input | punycode |
	// | --- | --- |
	// | `abc` | `abc-` |
	// | `bücher` | `bcher-kva` |
	// | `münchen` | `mnchen-3ya` |
	// | `αβγ` | `mxacd` |
	// | `мир` | `h1ahn` |
	// | `日本語` | `wgv71a119e` |
	// | `3年B組金八先生` | `3B-ww4c5e180e575a65lsy2b` |
	// | `-> $1.00 <-` | `-> $1.00 <--` |
	//
	// ## As a domain name
	//
	// Per label, and only where a label needed it: that is the `xn--` prefix.
	//
	// | unicode | wire form |
	// | --- | --- |
	// | `example.com` | `example.com` |
	// | `bücher.example` | `xn--bcher-kva.example` |
	// | `münchen.de` | `xn--mnchen-3ya.de` |
	// | `日本語.jp` | `xn--wgv71a119e.jp` |
	//
	// ## The ASCII stays readable
	//
	// Punycode is not a cipher over bytes. Every basic character is written out first, verbatim, and only the positions of the rest are compressed afterwards, so a mostly-ASCII label stays mostly legible:
	//
	// - `Hello-münchen-2024` encodes to `Hello-mnchen-2024-82b`
	// - and decodes back to `Hello-münchen-2024`
	//
	// > No nameprep, no normalization, no confusable check. This encodes what it is given, so it is a codec and not an answer to whether two domain names are the same.
}
