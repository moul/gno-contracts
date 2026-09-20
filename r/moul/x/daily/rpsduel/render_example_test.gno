package rpsduel

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Rock-Paper-Scissors Duel
	//
	// Challenge another address to rock-paper-scissors, async and fair: you commit your move as a hash, they reply in the open, then you reveal to settle it. Stall on revealing a losing round and your opponent can claim a forfeit win once the window expires.
	//
	// - Total duels resolved: 0
	// - No champion yet -- be the first to win a duel.
	//
	// ## How to play
	//
	// 1. Pick a move and a random salt, e.g. `rock` + `xyz123`.
	// 2. Compute your commitment: `ComputeCommit("rock", "xyz123")` (read-only call).
	// 3. `Open(opponentAddr, commit)` -- opens the duel, returns its ID.
	// 4. The opponent calls `Accept(id, "paper"|"scissors"|"rock")`.
	// 5. You call `Reveal(id, "rock", "xyz123")` -- must match your commitment exactly.
	// 6. If you never reveal, the opponent can call `ClaimForfeit(id)` after 50 blocks.
	//
	// View a duel at this realm's path plus its ID (e.g. `.../rpsduel:3`), or a player's record plus their address (e.g. `.../rpsduel:g1youraddress...`).
	//
	// ## Open duels
	//
	// _none right now_
}
