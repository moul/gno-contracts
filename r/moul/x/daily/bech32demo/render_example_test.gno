package bech32demo

// ExampleRender pins the realm's Render output as a testable example. The
// vectors are BIP-173's and BIP-350's, so this doubles as a conformance test,
// and the last table is the length-extension weakness reproduced in full.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Bech32
	//
	// Addresses that carry their own error-detecting checksum, demoing the [`p/moul/x/daily/bech32`](/p/moul/x/daily/bech32/v0) library.
	//
	// ## A gno.land address, taken apart
	//
	// Decoding g1manfred47kzduec920z88wfr64ylksmdcedlf5:
	//
	// | field | value |
	// | --- | --- |
	// | human-readable part | g |
	// | variant | bech32 |
	// | payload | 20 bytes |
	// | payload (hex) | `df6691e5b5f584de670553c473b923d549fb436d` |
	//
	// ## The two variants
	//
	// Same string shape, same data, different checksum constant: `1` for Bech32, `0x2bc830a3` for Bech32m.
	//
	// | Bech32 (BIP-173) | Bech32m (BIP-350) |
	// | --- | --- |
	// | `a12uel5l` | `a1lqfn3a` |
	// | `?1ezyfcl` | `?1v759aa` |
	// | `split1checkupstagehandshakeupstreamerranterredcaperred2y9e3w` | `split1checkupstagehandshakeupstreamerranterredcaperredlc445v` |
	//
	// ## Why Bech32m exists
	//
	// A Bech32 string ending in `p` keeps a valid checksum when `q` characters are inserted in front of that final `p`, so a reader accepts a string nobody wrote. Bech32m's constant closes it:
	//
	// | string | variant | verdict |
	// | --- | --- | --- |
	// | `a1q3g6mnsp` | bech32 | accepted |
	// | `a1q3g6mnsqp` | bech32 | accepted |
	// | `a1q6dp699p` | bech32m | accepted |
	// | `a1q6dp699qp` | - | rejected: bech32: bad checksum |
	//
	// Pass a string of your own to decode it: `Render("/<bech32 string>")`.
}
