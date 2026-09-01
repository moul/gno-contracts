package base32demo

// ExampleRender pins the realm's Render output as a testable example. The RFC
// 4648 column is the §10 vector set, so this doubles as a conformance test.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Base32
	//
	// RFC 4648 and Crockford, demoing the [`p/moul/x/daily/base32`](/p/moul/x/daily/base32/v1) library.
	//
	// | input | RFC 4648 | Crockford |
	// |---|---|---|
	// | _(empty)_ | `` | `` |
	// | `f` | `MY======` | `CR` |
	// | `fo` | `MZXQ====` | `CSQG` |
	// | `foo` | `MZXW6===` | `CSQPY` |
	// | `foob` | `MZXW6YQ=` | `CSQPYRG` |
	// | `fooba` | `MZXW6YTB` | `CSQPYRK1` |
	// | `foobar` | `MZXW6YTBOI======` | `CSQPYRK1E8` |
	//
	// ## Crockford forgives
	//
	// `hello` encodes to `D1JPRV3F`, and all of these decode back to it:
	//
	// - `D1JPRV3F` → `hello` ✅
	// - `d1jprv3f` → `hello` ✅
	// - `D1-JPRV3F` → `hello` ✅
	//
	// > Crockford folds case, reads `I`/`L` as `1` and `O` as `0`, and ignores hyphens — so an identifier survives being read aloud and typed back. `U` is left out of the alphabet on purpose.
}
