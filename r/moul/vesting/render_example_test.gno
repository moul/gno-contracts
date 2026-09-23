package vesting

// ExampleRender pins the index.
//
// reset() first, deliberately: an Example runs AFTER every Test in the package
// and sees the rows they declared, so without it this output depends on test
// order. The block time inside a gno test is fixed at 2009-02-13, before the
// real mainnet term starts, so the seeded row renders at 0% vested with the
// whole grant locked. That is a legitimate point on the curve and a stable one.
func ExampleRender() {
	reset()
	print(Render(""))
	// Output:
	// # Vesting
	//
	// How much of an account's balance can actually move right now.
	//
	// | account | balance | spendable | locked | vested |
	// | --- | --- | --- | --- | --- |
	// | moul `g1manfre…dlf5` | 0.000000 GNOT | 0.000000 GNOT | 0.000000 GNOT | 0.0% |
	//
	// ## Check another address
	//
	// Append it to the path: `/r/moul/vesting/v0:g1…`
	//
	// | | |
	// |---|---|
	// | put your own schedule on file | [Declare](/r/moul/vesting/v0$help&func=Declare&delayed=false&end=&original=&start=) |
	// | take it off again | [Forget](/r/moul/vesting/v0$help&func=Forget) |
	//
	// ## What is real here, and what is not
	//
	// | figure | where it comes from |
	// |---|---|
	// | balance | read from the chain every render, `banker.GetCoins` |
	// | the clock | read from the chain every render, the block time |
	// | the schedule | **supplied**, because no realm can read one |
	//
	// A realm's whole view of an account is its TOTAL balance, locked coins included. `std.VestingSchedule` lives in the auth store and no native reaches it, so the curve has to be told to this realm rather than found.
	//
	// That is safe to cache because a schedule can never change: it is set once, at genesis, and no message type creates or modifies one. A schedule declared correctly today is correct forever.
}
