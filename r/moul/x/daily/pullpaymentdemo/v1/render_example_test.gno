package pullpaymentdemo

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Pull Payment
	//
	// Credit and let recipients withdraw, demoing the [`p/moul/x/daily/pullpayment`](/p/moul/x/daily/pullpayment/v1) library.
	//
	// ## Why not just send?
	//
	// Pushing value hands control to the recipient in the middle of your state transition, and a hostile recipient re-enters before you have finished updating. Pulling inverts it: you record a debt, and the recipient's own withdrawal is the only state being touched.
	//
	// ## A split, credited
	//
	// | payee | owed |
	// |---|---|
	// | `alice` | 500 |
	// | `bob` | 300 |
	// | `carol` | 200 |
	//
	// The holding realm must keep `1000` in reserve — that is what `TotalOwed` is for.
	//
	// ## Bob claims
	//
	// `Withdraw("bob")` → `300`, and the ledger is updated **before** the caller transfers anything:
	//
	// | payee | owed |
	// |---|---|
	// | `alice` | 500 |
	// | `carol` | 200 |
	//
	// Reserve is now `700`.
	//
	// ## The reentrancy attempt
	//
	// Bob's handler calls straight back in, before the transfer completes:
	//
	// - second `Withdraw("bob")` → `0`, error: `pullpayment: nothing to withdraw`
	//
	// Nothing left to take. The balance was deleted before control left the function — checks, effects, *then* interactions. Lifetime withdrawn is still `300`, not double.
	//
	// ## Credits accumulate
	//
	// `Credit("alice", 100)` on top of her existing balance:
	//
	// | payee | owed |
	// |---|---|
	// | `alice` | 600 |
	// | `carol` | 200 |
	//
	// One withdrawal collects the lot — no dust left behind.
	//
	// ## Batch credits are all-or-nothing
	//
	// A split that is partly invalid applies **none** of itself; a ledger half-agreeing with the funds it guards is worse than a rejected call:
	//
	// - `CreditMany([dave, eve], [10, -1])` → `pullpayment: amount must be positive`
	// - total owed before: `800`, after: `800` — unchanged, and `dave` was not credited
}
