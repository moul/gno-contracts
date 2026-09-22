package faucet

// ExampleRender pins the faucet as it ships: no requests, an empty float, one
// approver. That IS the deployed state, since nothing is seeded here.
//
// reset() first: realm globals persist for the whole test binary and examples
// run after every Test. The float is NOT a realm global and reset() cannot
// clear it, so every test above withdraws what it funded; a test that leaves
// coins behind shows up as a diff here, which is the point.
func ExampleRender() {
	reset()
	print(Render(""))
	// Output:
	// # GNOT faucet
	//
	// Somebody you trust has no GNOT and cannot use the public faucet. File a
	// request on their behalf, an approver releases it, and both halves stay on
	// this page with a reason attached. The faucet only ever spends what has been
	// sent to its own address.
	//
	// | | |
	// | --- | ---: |
	// | Float available | **0 GNOT** |
	// | Paid out | 0 GNOT over 0 request(s) |
	// | Open requests | 0 |
	// | Refused | 0 |
	// | Cap per request | 200 GNOT |
	// | Float address | `g18jy5sp2hx5n8kkwvvs3l908ynyqdxgfh44ay88` |
	//
	// ## Open
	//
	// _Nothing here yet._
	//
	// ## Decided
	//
	// _Nothing here yet._
	//
	// ## Approvers
	//
	// - `g1manfred47kzduec920z88wfr64ylksmdcedlf5`
	//
	// ## How
	//
	// `Request(to, amount, reason)` is open to anyone and moves no money.
	// `Approve(id, to, amount)` pays it, and only an approver can call it.
	//
	// Send both in **one transaction**: a tm2 transaction stops at the first
	// message that fails and writes none of their state, so the ask and its
	// answer land together or not at all. Read `NextID` to address the approval,
	// and pass the recipient and the amount into it as well: if another request
	// takes that id first, the mismatch fails the transaction instead of paying
	// the wrong account.
}

// ExampleRenderUnknownRequest pins the per-request path on the one state it
// can reach deterministically from a reset faucet. A request page proper needs
// a crossing call to exist, and an Example func cannot take `cur realm`, so
// the filled-in version is asserted in TestRenderEscapesTheReason instead.
func ExampleRenderUnknownRequest() {
	reset()
	print(Render("req/7"))
	// Output:
	// # Request 7
	//
	// _No such request._
}
