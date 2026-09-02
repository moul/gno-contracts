package soundexdemo

// ExampleRender pins the realm's root Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Soundex
	//
	// Phonetic keys for English names, demoing the [`p/moul/x/daily/soundex`](/p/moul/x/daily/soundex/v1) library.
	//
	// | name | key |
	// |---|---|
	// | Robert | `R163` |
	// | Rupert | `R163` |
	// | Rubin | `R150` |
	// | Ashcraft | `A261` |
	// | Ashcroft | `A261` |
	// | Tymczak | `T522` |
	// | Pfister | `P236` |
	// | Honeyman | `H555` |
	//
	// ## Sounds alike
	//
	// - **R163**: Robert, Rupert
	// - **A261**: Ashcraft, Ashcroft
	//
	// > A *blocking* key for finding candidates, never proof that two names match.
}

// ExampleRender_noLetters pins the empty-key path: an input with no ASCII
// letters has no Soundex key at all, and must not be reported as matching.
func ExampleRender_noLetters() {
	print(Render("/12345"))
	// Output:
	// # Soundex
	//
	// Phonetic keys for English names, demoing the [`p/moul/x/daily/soundex`](/p/moul/x/daily/soundex/v1) library.
	//
	// ## `12345`
	//
	// _No ASCII letters — no key._
}
