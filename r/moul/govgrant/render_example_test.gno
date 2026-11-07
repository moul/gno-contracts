package govgrant

// ExampleRender pins the board as it is at deploy: nobody on it, the default
// cap, an empty treasury. That IS the shipped state: GovDAO seats the board
// and funds it afterwards, each by its own proposal.
//
// reset() first, since realm globals persist across the test binary. The
// treasury balance is not a global, so every test that issues coins spends
// them, and one that does not shows up as a diff here.
func ExampleRender() {
	reset()
	print(Render(""))
	// Output:
	// # GovDAO grant board
	//
	// A grant board funded by GovDAO. GovDAO sends the treasury money once; the
	// members below decide grants out of it, in the open, and every tranche leaves
	// only on a majority of them. A grant is not a GovDAO proposal: the board is.
	// Anyone may apply, or apply for someone whose account is empty.
	//
	// **GovDAO governs this board.** It seats the members, sets the cap, can pause
	// payouts and can take money back, each by a proposal its members vote on. The
	// members cannot change any of that themselves, and this realm's code cannot be
	// replaced. One request may ask for at most 50000000 ugnot in total.
	//
	// **You can ask for someone else.** `ApplyFor` takes the address the money goes
	// to and a reason for the detour, and prints both on the request. An account with
	// nothing in it cannot pay the gas to ask for its first coins, so someone else
	// filing is how most first grants arrive. Either address may submit the proofs,
	// and neither may vote on the request.
	//
	// ## Treasury
	//
	// | Field | Value |
	// |---|---|
	// | Address | `g1fuyr6eaqx7q06u89clgjaxmmnx7m64ar63exym` |
	// | Balance | 0 ugnot |
	// | Promised | 0 ugnot |
	// | Unpromised | 0 ugnot |
	// | Donated | 0 ugnot |
	// | Paid out | 0 ugnot |
	//
	// ## Board
	//
	// A decision needs a majority of the members eligible to cast a ballot on it,
	// recomputed every time: the party a decision is about never votes on it, so an
	// applicant who sits on the board shrinks the room rather than packing it.
	//
	// Nobody sits on this board, so nothing can be approved or paid.
	//
	// ## Requests
	//
	// Nothing has been asked of this board yet. `Apply` is open to anyone.
	//
	// ## Where the money went
	//
	// [The ledger](/r/moul/govgrant/v0:ledger) lists every donation in and every tranche
	// out, with the height, the payee and the milestone it paid for.
	//
	// ## Calling it
	//
	// ```sh
	// # put money in
	// gnokey maketx call -pkgpath gno.land/r/moul/govgrant/v0 -func Fund -send 5000000ugnot ...
	// # ask for some
	// gnokey maketx call -pkgpath gno.land/r/moul/govgrant/v0 -func Apply \
	//   -args 'Port the thing' -args 'why it matters' -args 'design:100,ship:400' ...
	// # ask on behalf of someone who cannot pay the gas to ask
	// gnokey maketx call -pkgpath gno.land/r/moul/govgrant/v0 -func ApplyFor \
	//   -args g1... -args 'their account is empty' \
	//   -args 'Port the thing' -args 'why it matters' -args 'design:100,ship:400' ...
	// # decide (members only)
	// gnokey maketx call -pkgpath gno.land/r/moul/govgrant/v0 -func Vote -args 1 -args true -args 'reason' ...
	// # show your work, then get paid for it
	// gnokey maketx call -pkgpath gno.land/r/moul/govgrant/v0 -func SubmitProof \
	//   -args 1 -args 0 -args url -args 'https://...' -args 'what it is' ...
	// gnokey maketx call -pkgpath gno.land/r/moul/govgrant/v0 -func Review -args 1 -args 0 -args true -args 'looks done' ...
	// ```
	//
	// Built on [p/moul/grants/v1](/p/moul/grants/v1), which holds every rule, every
	// tally and this page's markdown, and has no idea coins exist.
}
