package reaper

import (
	"strings"

	"gno.land/p/moul/x/storagecost/v0"
	"gno.land/p/nt/ufmt/v0"
)

// Every Example in this file is a *query*, and that is a constraint rather
// than a choice: an example function takes no arguments, so it never receives
// a `cur realm` and can never call Post, Reap or Compact. What is left is
// exactly the surface a reader of the live realm has without a key, so each
// one carries the `vm/qeval` line that produces the same answer on chain:
//
//	gnokey query vm/qeval -remote https://rpc.gno.land \
//	  -data 'gno.land/r/moul/x/reaper/v0.<expr>'
//
// The board is empty by the time these run, because every Test in this
// package drains what it posted and examples run after all of them.

// ExampleRender pins the page's skeleton: the title, the two sections that are
// always present, and the footer crediting the two packages that own the parts
// this realm does not.
//
//	vm/qrender  gno.land/r/moul/x/reaper/v0:
//
// It deliberately prints only the invariant lines. Everything interesting on
// the page is priced from the current block height and the notes outstanding,
// and an Example runs after every Test in the package and sees whatever state
// they left. The variable half is pinned by TestRenderShowsTheBountyAndTheReapLink
// instead, which controls the board first.
func ExampleRender() {
	for _, line := range strings.Split(Render(""), "\n") {
		switch {
		case strings.HasPrefix(line, "# "),
			strings.HasPrefix(line, "## "),
			strings.HasPrefix(line, "A noticeboard"),
			strings.HasPrefix(line, "The arithmetic is"):
			print(line + "\n")
		}
	}
	// Output:
	// # Reaper
	// A noticeboard whose garbage is a standing bounty. Posting a note locks a storage deposit. Once the note expires, anyone can delete it and the chain refunds that deposit **to whoever signs the deleting transaction**.
	// ## On the table right now
	// ## Board
	// The arithmetic is [p/moul/x/storagecost](/p/moul/x/storagecost/v0); the storage is [p/moul/ulist](/p/moul/ulist/v1), whose `Compact` reclaims dead nodes without moving a live index. Byte figures on this page are estimates from payload length: no stdlib call exposes a realm's real locked storage.
}

// ExampleReapable is the poll a reaping bot runs before it spends anything:
// three counters, three queries, no key and no gas.
//
//	vm/qeval  gno.land/r/moul/x/reaper/v0.Live()
//	vm/qeval  gno.land/r/moul/x/reaper/v0.Reapable()
//	vm/qeval  gno.land/r/moul/x/reaper/v0.Compactable()
//
// Reapable and Compactable are separate numbers because reaping and
// compacting are separate transactions, and compaction returns nothing at all
// while a live note still sits below the dead ones. A bot that sees
// `reapable 0, compactable 0` should not sign anything, which is the answer
// here.
func ExampleReapable() {
	print(ufmt.Sprintf("live %d, reapable %d, compactable %d\n",
		Live(), Reapable(), Compactable()))
	// Output:
	// live 0, reapable 0, compactable 0
}

// ExampleBounty is the single query that decides whether reaping is worth
// doing, and on an empty board it has to refuse to advertise a profit.
//
//	vm/qeval  gno.land/r/moul/x/reaper/v0.Bounty().String()
//
// Fee is what the reaping transaction costs at the floor gas price, and the
// chain charges it whether or not anything is freed. BreakEven turns that fee
// back into bytes: free fewer than 50 and the reaper is paying to tidy up.
// That threshold, not the size of the board, is what makes the mechanism a
// market rather than a chore.
func ExampleBounty() {
	print(Bounty().String() + "\n")
	// Output:
	// 0 bytes, refunds 0 GNOT against 0.005 GNOT of gas, break-even 50 bytes: not worth it yet
}

// ExampleBounty_worth is the same query answered by a board worth draining:
// ten expired notes of a kilobyte each.
//
// It recomputes the quote instead of posting, because an example has no
// `cur realm` to post with. The arithmetic is the one Bounty applies, so the
// numbers are the ones the live query would return with that board on it.
//
// This is the whole concept in two lines. The poster locked 1.8944 GNOT to
// occupy that space; a stranger who never posted anything spends 0.005 GNOT of
// gas to delete it and the chain hands them the deposit. Nobody minted a
// token, and no pool was funded.
func ExampleBounty_worth() {
	q := storagecost.EvaluateAtFloor(storagecost.EstimateBytes(10*1024), gasWantedReap)
	print(q.String() + "\n")
	print(ufmt.Sprintf("the reaper is paid %dx what the transaction costs\n", q.Refund/q.Fee))
	// Output:
	// 18944 bytes, refunds 1.8944 GNOT against 0.005 GNOT of gas, break-even 50 bytes: worth 1.8894 GNOT
	// the reaper is paid 378x what the transaction costs
}
