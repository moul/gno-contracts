package luhndemo

// ExampleRender pins the realm's root Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Luhn Checksum
	//
	// The mod-10 check behind card numbers and IMEIs, demoing the [`p/moul/x/daily/luhn`](/p/moul/x/daily/luhn/v1) library.
	//
	// Append a number to the path to check it — spaces and hyphens are ignored.
	//
	// ## Samples
	//
	// | number | valid? | note |
	// |---|---|---|
	// | `79927398713` | ✅ valid | the textbook example |
	// | `79927398710` | ❌ invalid | same number, wrong check digit |
	// | `4539148803436467` | ✅ valid | a test card number |
	// | `4539148803436647` | ❌ invalid | same card, two digits swapped |
	//
	// > Luhn is a **typo check, not a security check**: it catches every single-digit error and nearly every swap of adjacent digits, but anyone can compute a valid number. Never authorize anything with it.
}

// ExampleRender_invalid pins the repair path: a wrong check digit is reported
// along with the digit it should have been.
func ExampleRender_invalid() {
	print(Render("/79927398710"))
	// Output:
	// # Luhn Checksum
	//
	// The mod-10 check behind card numbers and IMEIs, demoing the [`p/moul/x/daily/luhn`](/p/moul/x/daily/luhn/v1) library.
	//
	// ## `79927398710`
	//
	// **Not valid.**
	//
	// Keeping the leading digits, the check digit should be **3** — i.e. `79927398713`.
}
