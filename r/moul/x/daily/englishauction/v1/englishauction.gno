// Package englishauction is an idiomatic gno.land port of the classic Solidity
// English (ascending-bid) auction. Anyone can Start an auction for a named item
// with a duration in blocks; bidders call Bid with a strictly increasing amount.
// The previous highest bid becomes refundable (claim it with Withdraw). After
// the auction's end height anyone may call End, awarding the item to the highest
// bidder. Auctions and pending refunds live in ordered avl trees so Render can
// iterate deterministically.
package englishauction

import (
	"strconv"

	"chain"
	"chain/runtime"
	"chain/runtime/unsafe"

	"gno.land/p/moul/kit/store/v0"
	"gno.land/p/nt/avl/v0"
)

// Auction is a single ascending-bid auction. It carries no ID field: the id
// belongs to the store, which hands it back on lookup and iteration.
type Auction struct {
	Seller        address
	Item          string
	EndHeight     int64
	HighestBid    uint64
	HighestBidder address
	Ended         bool
}

var (
	// auctions assigns the auction ids. v0 kept its own nextID plus a key()
	// that zero-padded to width 12, which stopped ordering Render past 10^12.
	auctions = store.Named("englishauction: auction")

	pending avl.Tree // "<id>:<addr>" -> uint64 refundable amount
)

// pendKey formats the refund key for a given auction id and bidder. It uses
// the decimal id rather than the store key: pending is only ever point-read,
// never iterated, so it needs a readable key and not an ordered one.
func pendKey(id int64, bidder address) string {
	return strconv.FormatInt(id, 10) + ":" + bidder.String()
}

// Start opens a new auction for `item` running for `durationBlocks` blocks from
// the current height. The caller becomes the seller. Returns the auction id.
func Start(cur realm, item string, durationBlocks int64) int64 {
	if item == "" {
		panic("englishauction: item must not be empty")
	}
	if durationBlocks <= 0 {
		panic("englishauction: duration must be > 0 blocks")
	}
	seller := unsafe.PreviousRealm().Address()
	a := &Auction{
		Seller:    seller,
		Item:      item,
		EndHeight: runtime.ChainHeight() + durationBlocks,
	}
	id := int64(auctions.Add(a))

	chain.Emit("Start",
		"id", strconv.FormatInt(id, 10),
		"seller", seller.String(),
		"item", item,
		"endHeight", strconv.FormatInt(a.EndHeight, 10),
	)
	return id
}

// Bid places a bid of `amount` on auction `id`. It must strictly exceed the
// current highest bid. The displaced highest bid becomes refundable to its
// bidder via Withdraw.
func Bid(cur realm, id int64, amount uint64) {
	a := mustGet(id)
	if a.Ended || runtime.ChainHeight() >= a.EndHeight {
		panic("englishauction: auction has ended")
	}
	if amount <= a.HighestBid {
		panic("englishauction: bid must strictly exceed current highest")
	}
	bidder := unsafe.PreviousRealm().Address()
	if bidder == a.Seller {
		panic("englishauction: seller cannot bid")
	}

	// The prior top bid becomes refundable (accumulate in case of repeats).
	if a.HighestBid > 0 {
		pk := pendKey(id, a.HighestBidder)
		pending.Set(pk, pendingOf(id, a.HighestBidder)+a.HighestBid)
	}

	a.HighestBid = amount
	a.HighestBidder = bidder

	chain.Emit("Bid",
		"id", strconv.FormatInt(id, 10),
		"bidder", bidder.String(),
		"amount", strconv.FormatUint(amount, 10),
	)
}

// Withdraw refunds the caller's accumulated displaced bids for auction `id`.
// Returns the amount refunded (0 if nothing pending).
func Withdraw(cur realm, id int64) uint64 {
	mustGet(id) // ensure auction exists
	caller := unsafe.PreviousRealm().Address()
	amount := pendingOf(id, caller)
	if amount == 0 {
		return 0
	}
	pending.Remove(pendKey(id, caller))
	chain.Emit("Withdraw",
		"id", strconv.FormatInt(id, 10),
		"bidder", caller.String(),
		"amount", strconv.FormatUint(amount, 10),
	)
	return amount
}

// End closes auction `id` once its end height is reached, awarding the item to
// the highest bidder (if any). Anyone may call it.
func End(cur realm, id int64) {
	a := mustGet(id)
	if a.Ended {
		panic("englishauction: auction already ended")
	}
	if runtime.ChainHeight() < a.EndHeight {
		panic("englishauction: auction not yet over")
	}
	a.Ended = true

	chain.Emit("End",
		"id", strconv.FormatInt(id, 10),
		"winner", a.HighestBidder.String(),
		"amount", strconv.FormatUint(a.HighestBid, 10),
	)
}

// --- read-only helpers (safe from tests and Render) ---

// mustGet returns the auction for `id`, panicking if it does not exist. The
// store's label puts the id in the message, which v0's fixed string
// ("englishauction: no such auction") left out.
func mustGet(id int64) *Auction {
	return auctions.MustGet(store.ID(id)).(*Auction)
}

// pendingOf returns the refundable amount owed to `bidder` for auction `id`.
func pendingOf(id int64, bidder address) uint64 {
	v := pending.Get(pendKey(id, bidder))
	if v == nil {
		return 0
	}
	return v.(uint64)
}

// blocksLeft returns how many blocks remain before `a` can be ended (0 if the
// end height has been reached).
func blocksLeft(a *Auction, height int64) int64 {
	if height >= a.EndHeight {
		return 0
	}
	return a.EndHeight - height
}

// hasWinner reports whether the auction received at least one bid.
func hasWinner(a *Auction) bool {
	return a.HighestBid > 0
}

// Render lists every auction with item, top bid + bidder, time left, and winner.
func Render(path string) string {
	out := "# English Auction\n\n"
	out += "Ascending-bid auctions. Start one, outbid others, and End it after "
	out += "its block deadline to award the item to the top bidder.\n\n"

	if auctions.Len() == 0 {
		out += "_No auctions yet. Call `Start` to open one._\n"
		return out
	}

	height := runtime.ChainHeight()
	out += "_Current block height: " + strconv.FormatInt(height, 10) + "_\n\n"
	out += "| ID | Item | Highest Bid | Bidder | Status | Winner |\n"
	out += "|---:|------|------------:|--------|--------|--------|\n"

	auctions.Each(func(id store.ID, v any) {
		a := v.(*Auction)

		bidStr := "—"
		bidderStr := "—"
		if hasWinner(a) {
			bidStr = strconv.FormatUint(a.HighestBid, 10)
			bidderStr = "`" + a.HighestBidder.String() + "`"
		}

		status := ""
		winner := "—"
		switch {
		case a.Ended:
			status = "ended"
			if hasWinner(a) {
				winner = "`" + a.HighestBidder.String() + "`"
			} else {
				winner = "no bids"
			}
		case height >= a.EndHeight:
			status = "awaiting End"
		default:
			status = strconv.FormatInt(blocksLeft(a, height), 10) + " blocks left"
		}

		out += "| " + id.String() + " | " + a.Item + " | " +
			bidStr + " | " + bidderStr + " | " + status + " | " + winner + " |\n"
	})
	return out
}
