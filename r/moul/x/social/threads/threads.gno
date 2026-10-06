// Package threads is a discussion block any realm can embed, keyed on the page
// it appears on rather than on the realm that stores it.
//
// It is the text half of gno.land/r/moul/reactions: the same embed shape, the
// same page keys, two lines in the host realm.
//
//	import "gno.land/r/moul/x/social/threads/v0"
//
//	func Render(path string) string {
//		return body + threads.RenderBlock()
//	}
//
// [RenderBlock] takes no argument because it does not need one: a plain read
// exported by a realm and called by another opens no realm frame, so
// unsafe.CurrentRealm() inside it reports the CALLER. The host realm's own
// path is the page key, and nothing has to be configured or registered.
// [RenderBlockFor] is the explicit form, for a realm that renders more than
// one page or already holds its path as a constant.
//
// # The token, and the three things it has to answer
//
// THREAD exists because placement is the one thing a discussion has that
// people want and cannot all have at once.
//
//	mint   1 THREAD to a thread's author, the first time each distinct
//	       address replies to it. People, not messages, and never yourself.
//	sink   [Boost] burns PinCost THREAD to pin a thread to the top of its
//	       page for PinBlocks blocks. That is the only thing that removes
//	       supply, and the only thing the token does.
//	buyer  anyone who wants placement and has not earned it. They have to
//	       acquire THREAD from someone who did, with [Transfer], which is
//	       what makes attention a market rather than a scoreboard.
//
// It is farmable, and saying so is cheaper than pretending otherwise: two
// addresses replying to each other mint one THREAD each per thread. The fix is
// a gate on who counts as a replier, which belongs in a vouching realm and not
// here; until then the cost of farming is one transaction per point and the
// benefit is capped by what a pin is worth.
package threads

import (
	"chain"
	"chain/runtime"
	"chain/runtime/unsafe"
	"strconv"

	"gno.land/p/moul/kit/store/v0"
	sc "gno.land/p/moul/x/social/coin/v0"
	th "gno.land/p/moul/x/social/threads/v0"
	"gno.land/r/nt/grc20reg/v0"
)

// realmPath is this realm's own path, the one its gnomod.toml module line
// declares. It is written out rather than read from unsafe.CurrentRealm(),
// which reports the CALLER in every plain read this realm exports and would
// therefore build every link against whichever realm embedded the block.
const realmPath = "gno.land/r/moul/x/social/threads/v0"

const (
	// EarnPerReplier is minted to a thread's author the first time each
	// distinct address replies to it.
	EarnPerReplier = int64(1)

	// PinCost is burned by Boost, and PinBlocks is how long the pin lasts.
	// A pin extends from whichever is later, now or the current pin, so
	// buying one never shortens somebody else's.
	PinCost   = int64(10)
	PinBlocks = int64(1000)

	// BlockThreads is how many threads an embedded block shows before it
	// turns into a link to the full page.
	BlockThreads = 5
)

var (
	// board holds every thread. A redeploy would wipe it, which is why this
	// realm is not private (see gnomod.toml).
	board = th.NewBoard()

	// points is the THREAD ledger. The Coin is unexported on purpose: it
	// carries unrestricted mint and burn, and an exported pointer to it
	// would hand both to any importer.
	points *sc.Coin

	// tokenKey is the r/nt/grc20reg lookup key, which is how a realm that
	// does not import this one refers to THREAD.
	tokenKey string
)

// tokenPolicy is the three declarations THREAD is issued under. It is a var
// and not three literals inside init so that the tests, which rebuild the
// ledger between cases, issue the same token the chain holds.
var tokenPolicy = sc.Policy{
	Mint:  "1 to a thread's author per distinct address that replies to it",
	Sink:  "burned by Boost to pin a thread to the top of its page",
	Buyer: "anyone who wants placement and has not earned it",
}

func init(cur realm) {
	points = sc.New("Thread Points", "THREAD", 0, 0, tokenPolicy, 0, cur)
	tokenKey = grc20reg.Register(cross(cur), points.Token(), "thread")
}

// Post opens a thread under page.
//
// page is a package path, the full one: "gno.land/r/moul/home". It does not
// have to be a realm that embeds the block, and nothing checks that it exists.
// A page is just a name, which is what lets a realm key discussion on
// something finer than itself.
func Post(cur realm, page, body string) int64 {
	who := caller(cur)
	id, err := board.Post(page, who, body, runtime.ChainHeight())
	if err != nil {
		panic(err.Error())
	}
	chain.Emit("Post", "id", id.String(), "page", page, "author", who.String())
	return int64(id)
}

// Reply appends to a thread.
//
// The first time each distinct address replies to a given thread, its author
// earns EarnPerReplier. Replying again earns nothing, and replying to your own
// thread never earns anything.
func Reply(cur realm, threadID int64, body string) {
	who := caller(cur)
	id := store.ID(threadID)
	isNew, err := board.Reply(id, who, body, runtime.ChainHeight())
	if err != nil {
		panic(err.Error())
	}
	chain.Emit("Reply", "id", id.String(), "author", who.String())

	if isNew {
		t, _ := board.Get(id)
		points.Earn(t.Author, EarnPerReplier)
		chain.Emit("Earn", "id", id.String(), "author", t.Author.String())
	}
}

// Boost burns PinCost THREAD from the caller and pins the thread to the top of
// its page for PinBlocks blocks.
//
// Anyone may boost anyone's thread. The pin is on the thread and not on the
// buyer, so the thing being sold is placement and not authorship.
func Boost(cur realm, threadID int64) {
	who := caller(cur)
	id := store.ID(threadID)
	t, ok := board.Get(id)
	if !ok {
		panic(th.ErrNoThread.Error())
	}

	now := runtime.ChainHeight()
	from := now
	if t.PinnedUntil > from {
		from = t.PinnedUntil
	}
	// Charge first, pin second. The chain would revert both on an abort, so
	// the order is invisible on mainnet and load-bearing everywhere else: a
	// test, a filetest and any future caller that recovers see a refused
	// boost that pinned nothing.
	points.Spend(who, PinCost)
	if err := board.Pin(id, from+PinBlocks); err != nil {
		panic(err.Error())
	}
	chain.Emit("Boost", "id", id.String(), "by", who.String(),
		"until", strconv.FormatInt(from+PinBlocks, 10))
}

// Transfer moves the caller's own THREAD. It is what makes the sink a market:
// somebody who wants a pin and has written nothing has to buy from an author.
func Transfer(cur realm, to address, amount int64) {
	if err := points.CallerTeller().Transfer(0, cur, to, amount); err != nil {
		panic(err.Error())
	}
}

// Approve lets spender draw amount of the caller's THREAD.
func Approve(cur realm, spender address, amount int64) {
	if err := points.CallerTeller().Approve(0, cur, spender, amount); err != nil {
		panic(err.Error())
	}
}

// TransferFrom spends an allowance the caller was granted.
func TransferFrom(cur realm, from, to address, amount int64) {
	if err := points.CallerTeller().TransferFrom(0, cur, from, to, amount); err != nil {
		panic(err.Error())
	}
}

// RenderBlock returns the block for the realm CALLING it, which is the form a
// host realm embeds.
//
// It has no cur realm parameter on purpose. A plain read is borrowed: gno
// opens no realm frame for it, so unsafe.CurrentRealm() reports the caller's
// path and the block keys itself with no argument. Adding a cur realm here
// would silently reverse that and key every embed to this realm instead.
func RenderBlock() string {
	return blockFor(unsafe.CurrentRealm().PkgPath())
}

// RenderBlockFor is [RenderBlock] for a named page. Use it from a crossing
// function, where there is no caller to read off the stack, or when one realm
// renders several pages.
func RenderBlockFor(page string) string { return blockFor(page) }

// blockFor is the shared body, so no exported read of this realm calls another
// and picks up the wrong path.
func blockFor(page string) string {
	now := runtime.ChainHeight()
	return th.Block(realmPath, page, board.List(page, now, BlockThreads), board.PageLen(page), now)
}

// Count is how many threads a page holds.
func Count(page string) int { return board.PageLen(page) }

// Total is how many threads exist, across every page.
func Total() int { return board.Len() }

// Pages is how many pages have ever been posted on.
func Pages() int { return board.Pages() }

// Repliers is how many distinct addresses have replied to a thread, which is
// also how much its author has earned from it.
func Repliers(threadID int64) int {
	t, _ := board.Get(store.ID(threadID))
	return t.Repliers()
}

// PinnedUntil is the height a thread stops being pinned at, or 0.
func PinnedUntil(threadID int64) int64 {
	t, ok := board.Get(store.ID(threadID))
	if !ok {
		return 0
	}
	return t.PinnedUntil
}

// BalanceOf is an address's THREAD balance.
func BalanceOf(owner address) int64 { return points.BalanceOf(owner) }

// Allowance is what owner let spender draw.
func Allowance(owner, spender address) int64 {
	return points.Token().Allowance(owner, spender)
}

// TotalSupply is the THREAD in existence: everything earned, less everything
// burned by Boost.
func TotalSupply() int64 { return points.Supply() }

// TokenKey is the r/nt/grc20reg key for THREAD.
func TokenKey() string { return tokenKey }

// caller is the address that called us, checked the one way that is safe.
func caller(cur realm) address {
	if !cur.IsCurrent() {
		panic("spoofed realm: cur is not the live crossing frame")
	}
	return cur.Previous().Address()
}
