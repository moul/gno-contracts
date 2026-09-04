package cliffvestingdemo

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Cliff Vesting
	//
	// A pure vesting calculator, demoing the [`p/moul/x/daily/cliffvesting`](/p/moul/x/daily/cliffvesting/v1) library.
	//
	// ## A 12-month grant with a 3-month cliff
	//
	// `1200` tokens, `Start = 0`, `Cliff = 3`, `End = 12`.
	//
	// | month | vested | unvested | % |
	// |---|---|---|---|
	// | 0 | 0 | 1200 | 0% |
	// | 1 | 0 | 1200 | 0% |
	// | 2 | 0 | 1200 | 0% ← nothing yet |
	// | 3 | 300 | 900 | 25% ← **cliff** |
	// | 4 | 400 | 800 | 33% |
	// | 5 | 500 | 700 | 41% |
	// | 6 | 600 | 600 | 50% |
	// | 7 | 700 | 500 | 58% |
	// | 8 | 800 | 400 | 66% |
	// | 9 | 900 | 300 | 75% |
	// | 10 | 1000 | 200 | 83% |
	// | 11 | 1100 | 100 | 91% |
	// | 12 | 1200 | 0 | 100% ← fully vested |
	//
	// The cliff is a **step, not a ramp**: at month 3 a quarter of the term has elapsed, so `300` tokens unlock at once. After that it accrues linearly.
	//
	// ## Claiming
	//
	// The library tracks no balances — the caller supplies what has already been claimed:
	//
	// | at month | already claimed | claimable |
	// |---|---|---|
	// | 6 | 0 | 600 |
	// | 6 | 300 | 300 |
	// | 6 | 600 | 0 |
	// | 12 | 600 | 600 |
	//
	// ## Integer rounding
	//
	// All arithmetic is integer — no float ever reaches consensus state. Rounding is **down**, so nobody is ever paid more than they earned, and the final instalment collects the remainder.
	//
	// `1000` over `3` periods:
	//
	// | t | vested |
	// |---|---|
	// | 0 | 0 |
	// | 1 | 333 |
	// | 2 | 666 |
	// | 3 | 1000 |
	//
	// `333 + 333 + 334` — the end is exactly `1000`, never `999`.
	//
	// ## The bug this avoids
	//
	// When the total is smaller than the duration, computing a per-tick rate first truncates it to zero and **nothing ever vests**. Multiplying before dividing keeps it honest — `7` tokens over `1000` ticks:
	//
	// | t | vested |
	// |---|---|
	// | 100 | 0 |
	// | 150 | 1 |
	// | 500 | 3 |
	// | 1000 | 7 |
}
