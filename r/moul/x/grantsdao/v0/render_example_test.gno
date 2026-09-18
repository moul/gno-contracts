package grantsdao

// ExampleRender pins the board's front page.
//
// It calls seed() first: realm globals persist for the whole test binary and
// examples run after every Test, so without the reset this output would
// depend on what the tests left behind. The treasury BALANCE is not a realm
// global and seed() cannot reset it, so the tests are written to be
// balance-neutral (TestFullLifecyclePaysThroughTheBanker pays out exactly
// what it funds). A test that issues coins and does not spend them will show
// up as a diff here, which is the point.
func ExampleRender() {
	seed()
	print(Render(""))
	// Output:
	// # Grants DAO
	//
	// Anyone may ask this board for money. The members decide in the open, and the
	// money leaves one milestone at a time, each tranche against a proof the board
	// accepted. Every ballot on this page carries the name of who cast it and the
	// reason they gave, including the ones on proofs that were refused.
	//
	// ## Treasury
	//
	// | Field | Value |
	// |---|---|
	// | Address | `g1agrk4dzp069z66lt3fkzvfrkvqgmkm0u7w6f7f` |
	// | Balance | 0 ugnot |
	// | Promised | 2000 ugnot |
	// | Unpromised | -2000 ugnot |
	// | Donated | 0 ugnot |
	// | Paid out | 0 ugnot |
	//
	// The board has promised 2000 ugnot more than it holds. Approving a grant
	// does not escrow anything, so a tranche can come due against an empty treasury;
	// a review that would release one is refused until the money is there. Top it up
	// with `Fund`, or by sending ugnot straight to the address above.
	//
	// ## Board
	//
	// A decision needs a majority of the members eligible to cast a ballot on it,
	// recomputed every time: the party a decision is about never votes on it, so an
	// applicant who sits on the board shrinks the room rather than packing it.
	//
	// | Member | Joined at height |
	// |---|---|
	// | `g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5` | 0 |
	// | `g1manfred47kzduec920z88wfr64ylksmdcedlf5` | 0 |
	// | `g1us8428u2a5satrlxzagqqa5m6vmuze025anjlj` | 0 |
	// | `g1vaexzmn5wvkk6etdvfjhytf5ta047h6lyrpr58` | 102 |
	//
	// ## Requests
	//
	// | # | Kind | Title | Asking | Status | Ballots |
	// |---|---|---|---|---|---|
	// | [1](/r/moul/x/grantsdao/v0:request/1) | membership | Add g1vaexzmn5wvkk6etdvfjhytf5ta047h6lyrpr58 | nothing | completed | 2 for, 0 against |
	// | [2](/r/moul/x/grantsdao/v0:request/2) | grant | Port the p/nt/avl benchmarks to gno | 2000 ugnot | approved | 3 for, 1 against |
	// | [3](/r/moul/x/grantsdao/v0:request/3) | grant | Rewrite gnoweb in a different framework | 250000 ugnot | rejected | 0 for, 3 against |
	//
	// ## Where the money went
	//
	// [The ledger](/r/moul/x/grantsdao/v0:ledger) lists every donation in and every tranche out,
	// with the height, the payee and the milestone it paid for.
	//
	// ## Calling it
	//
	// ```sh
	// # put money in
	// gnokey maketx call -pkgpath gno.land/r/moul/x/grantsdao/v0 -func Fund -send 5000000ugnot ...
	// # ask for some
	// gnokey maketx call -pkgpath gno.land/r/moul/x/grantsdao/v0 -func Apply \
	//   -args 'Port the thing' -args 'why it matters' -args 'design:100,ship:400' ...
	// # decide (members only)
	// gnokey maketx call -pkgpath gno.land/r/moul/x/grantsdao/v0 -func Vote -args 4 -args true -args 'reason' ...
	// # show your work, then get paid for it
	// gnokey maketx call -pkgpath gno.land/r/moul/x/grantsdao/v0 -func SubmitProof \
	//   -args 4 -args 0 -args url -args 'https://…' -args 'what it is' ...
	// gnokey maketx call -pkgpath gno.land/r/moul/x/grantsdao/v0 -func Review -args 4 -args 0 -args true -args 'looks done' ...
	// ```
	//
	// Built on [p/moul/x/grants/v0](/p/moul/x/grants/v0), which holds the state
	// machine and no coins.
}

// ExampleRenderRequest pins the richest page: a grant mid-delivery, with
// every ballot, its reason, and the proof currently under review.
func ExampleRenderRequest() {
	seed()
	print(Render("request/2"))
	// Output:
	// # Request 2: Port the p/nt/avl benchmarks to gno
	//
	// | Field | Value |
	// |---|---|
	// | Kind | grant |
	// | Applicant | `g1vaexzmn5wvkkzursd35kxctww3047h6lhfh8j5` |
	// | Status | approved |
	// | Filed at height | 110 |
	// | Decided at height | 114 |
	// | Asking | 2000 ugnot |
	// | Paid so far | 0 ugnot |
	// | Still owed | 2000 ugnot |
	//
	// > Seeded at deploy, not filed by anyone. `g1vaexzmn5wvkkzursd35kxctww3047h6lhfh8j5`
	// > is a placeholder with a valid checksum and no key behind it, so this request
	// > can never be carried further by its applicant, and a tranche released to it
	// > would go nowhere. It is here to show the shape of a live one.
	//
	// ## The ask
	//
	// Three weeks. Deliverables are a benchmark harness, a report on the tree rebalancing costs, and a PR against the monorepo.
	//
	// ## Ballots
	//
	// Needs 3 of 4 eligible members. Standing: 3 for, 1 against.
	//
	// | Member | Vote | Height | Reason |
	// |---|---|---|---|
	// | `g1manfred47kzduec920z88wfr64ylksmdcedlf5` | for | 111 | Cheap for what it tells us. |
	// | `g1us8428u2a5satrlxzagqqa5m6vmuze025anjlj` | against | 112 | The second milestone is vague. |
	// | `g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5` | for | 113 | Vague but bounded. Worth it. |
	// | `g1vaexzmn5wvkk6etdvfjhytf5ta047h6lyrpr58` | for | 114 | Agreed with carol. |
	//
	// ## Milestones
	//
	// Earned in order. The applicant submits a proof, the board reviews that proof,
	// and the verdict that carries also moves the coins.
	//
	// ### 1. harness merged: 1200 ugnot
	//
	// A proof is under review.
	//
	// **Proof 1** (url, height 120, under review)
	//
	// ```
	// https://github.com/gnolang/gno/pull/9999
	// ```
	//
	// Harness merged, 14 benchmarks, runs in CI.
	//
	// | Member | Vote | Height | Reason |
	// |---|---|---|---|
	// | `g1manfred47kzduec920z88wfr64ylksmdcedlf5` | accept | 121 | Merged, I reviewed it. |
	//
	// ### 2. report published: 800 ugnot
	//
	// Locked until milestone 1 is released.
}

// ExampleRenderLedger pins the money trail of a board nobody has funded yet.
func ExampleRenderLedger() {
	seed()
	print(Render("ledger"))
	// Output:
	// # Grants DAO: the ledger
	//
	// Every coin in and every coin out, in the order it happened. Coins sent
	// straight to `g1agrk4dzp069z66lt3fkzvfrkvqgmkm0u7w6f7f` land in the treasury
	// without appearing here, which is why `Fund` exists: it is the same transfer
	// with a name attached.
	//
	// ## In
	//
	// Nothing donated through `Fund` yet.
	//
	// ## Out
	//
	// No tranche has been released yet.
	//
	// Balance now: 0 ugnot. [Back to the board](/r/moul/x/grantsdao/v0).
}
