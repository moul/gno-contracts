package fractiondemo

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Fractions
	//
	// Exact rational arithmetic, demoing the [`p/moul/x/daily/fraction`](/p/moul/x/daily/fraction/v1) library.
	//
	// ## A third, three times
	//
	// `1/3 + 1/3 + 1/3` = **1**, exactly — not 0.9999…
	//
	// As a decimal it is only ever an approximation: `0.3333333333`
	//
	// ## Arithmetic
	//
	// | expression | result |
	// |---|---|
	// | `1/2 + 1/3` | `5/6` |
	// | `1/2 - 1/3` | `1/6` |
	// | `1/2 × 1/3` | `1/6` |
	// | `1/2 ÷ 1/3` | `3/2` |
	//
	// ## Exact comparison
	//
	// `1/3` vs `33333/100000` — identical to five decimal places, yet the library still knows which is larger: **1/3 is greater**
	//
	// > Comparison cross-multiplies, so it never takes a decimal detour. There are no floats here: on a chain, an answer that depends on rounding is a consensus bug.
}
