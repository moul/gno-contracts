package coinflipduel

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Coin-Flip Duel
	//
	// Challenge another address to a coin flip. You call heads or tails up front; they accept and the block decides. No stakes -- just a record.
	//
	// - Total duels resolved: 0
	// - No champion yet -- be the first to win a duel.
	//
	// ## How to play
	//
	// 1. `Challenge(opponentAddr, "heads"|"tails")` -- opens a duel, returns its ID.
	// 2. The opponent calls `Accept(id)` -- flips the coin and settles it on the spot.
	// 3. The challenger may `Cancel(id)` while it's still pending.
	//
	// View a duel at this realm's path plus its ID (e.g. `.../coinflipduel:3`), or a player's record plus their address (e.g. `.../coinflipduel:g1youraddress...`).
	//
	// ## Pending duels
	//
	// _none right now_
}
