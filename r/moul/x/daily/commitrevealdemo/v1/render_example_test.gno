package commitrevealdemo

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Commit–Reveal
	//
	// Bind to a choice without disclosing it, demoing the [`p/moul/x/daily/commitreveal`](/p/moul/x/daily/commitreveal/v1) library.
	//
	// ## The problem
	//
	// A transaction is public before it executes. In a sealed-bid auction or a simultaneous-move game, whoever moves last reads everyone else's move and wins for free.
	//
	// ## Phase 1 — commit
	//
	// Each player publishes only `H(value ‖ salt)`. Nothing about the move leaks, but neither can change it later.
	//
	// | player | commitment |
	// |---|---|
	// | alice | `11811a2d4eede29f…` |
	// | bob | `db066e8c917e07d5…` |
	//
	// ## Phase 2 — reveal
	//
	// Now the values and salts are published and checked against the commitments recorded earlier:
	//
	// | check | result |
	// |---|---|
	// | alice opens with `rock` | ✅ accepted |
	// | bob opens with `paper` | ✅ accepted |
	// | bob tries `scissors` instead | ❌ `commitreveal: reveal does not match the commitment` |
	// | bob claims alice's commitment | ❌ `commitreveal: reveal does not match the commitment` |
	//
	// Bob cannot switch his move after seeing Alice's, and cannot pass off her commitment as his own.
	//
	// ## Why the salt is mandatory
	//
	// Rock-paper-scissors has three possible moves. Without a salt there are exactly three possible hashes, and hashing all three breaks the scheme outright. The library refuses a salt shorter than `16` bytes rather than leaving that as advice:
	//
	// - `Commit("rock", "tooshort")` → `commitreveal: salt is shorter than MinSaltLen`
	//
	// The salt also keeps two players who pick the *same* move from publishing the same commitment:
	//
	// | same move, different salt | commitment |
	// |---|---|
	// | player 1 | `a5d84fa94157acca…` |
	// | player 2 | `ccbc5d0b7ab1e84d…` |
	//
	// ## Two details that are easy to get wrong
	//
	// - **Length-prefixed hashing.** With plain concatenation `("ab","cd…")` and `("abc","d…")` hash identically, so one commitment could be opened two different ways.
	// - **Constant-time comparison.** A short-circuiting check leaks, through timing, how many leading bytes of a guess were right — enough to rebuild a commitment byte by byte.
}
