package wrapped

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Wrapped (WETH-style, accounting-only)
	//
	// Deposit mints wrapped units, Withdraw burns them. No real coins move — this is a pure ledger.
	//
	// **Total supply:** 0
	//
	// _No balances yet. Call `Deposit` to wrap some units._
}
