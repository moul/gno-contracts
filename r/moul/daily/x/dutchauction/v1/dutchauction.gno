// Package dutchauction ports the classic Solidity Dutch-auction pattern to
// gno.land: a seller lists an item at a high starting price that decays
// linearly, block by block, down to a floor price. The first buyer to call
// Buy pays whatever the price is at that moment — real ugnot, escrowed by
// the chain with the transaction and forwarded to the seller on settlement.
// Overpayment is refunded automatically. State-mutating functions are
// crossing functions (`cur realm`) per the gno 0.9 interrealm convention.
package dutchauction

import (
	"errors"
	"strconv"
	"strings"

	"chain"
	"chain/banker"
	"chain/runtime"
	"chain/runtime/unsafe"

	"gno.land/p/nt/avl/v0"
)

const denom = "ugnot"

type status int

const (
	statusActive status = iota
	statusSold
	statusCancelled
)

func (s status) String() string {
	switch s {
	case statusActive:
		return "active"
	case statusSold:
		return "sold"
	case statusCancelled:
		return "cancelled"
	default:
		return "unknown"
	}
}

// auction is one listing: price falls linearly from StartPrice to
// FloorPrice over Duration blocks starting at StartHeight, then holds flat
// at FloorPrice until bought or cancelled.
type auction struct {
	ID          string
	Item        string
	Seller      address
	StartPrice  int64
	FloorPrice  int64
	StartHeight int64
	Duration    int64
	Status      status
	Buyer       address
	SoldPrice   int64
}

var (
	auctions    avl.Tree // id string -> *auction
	nextID      uint64
	totalListed uint64
	totalSold   uint64
	totalVolume int64
)

var (
	errEmptyItem    = errors.New("dutchauction: item description required")
	errBadPrice     = errors.New("dutchauction: startPrice must be greater than floorPrice, floorPrice must be >= 0")
	errBadDuration  = errors.New("dutchauction: durationBlocks must be positive")
	errNotFound     = errors.New("dutchauction: auction not found")
	errNotActive    = errors.New("dutchauction: auction is not active")
	errNotSeller    = errors.New("dutchauction: caller is not the seller")
	errNotUserCall  = errors.New("dutchauction: buy must be a direct user transaction")
	errUnderpaid    = errors.New("dutchauction: payment below current price")
	errSpoofedRealm = errors.New("dutchauction: spoofed realm")
)

// caller authenticates the crossing frame and returns the immediate caller.
func caller(cur realm) address {
	if !cur.IsCurrent() {
		panic(errSpoofedRealm)
	}
	return cur.Previous().Address()
}

// List creates a new Dutch auction for item, starting at startPrice ugnot
// and falling linearly to floorPrice over durationBlocks. Returns the new
// auction's ID. Crossing function.
func List(cur realm, item string, startPrice, floorPrice, durationBlocks int64) string {
	seller := caller(cur)

	item = strings.TrimSpace(item)
	if item == "" {
		panic(errEmptyItem)
	}
	if floorPrice < 0 || startPrice <= floorPrice {
		panic(errBadPrice)
	}
	if durationBlocks <= 0 {
		panic(errBadDuration)
	}

	nextID++
	id := strconv.FormatUint(nextID, 10)
	auctions.Set(id, &auction{
		ID:          id,
		Item:        item,
		Seller:      seller,
		StartPrice:  startPrice,
		FloorPrice:  floorPrice,
		StartHeight: runtime.ChainHeight(),
		Duration:    durationBlocks,
		Status:      statusActive,
	})
	totalListed++
	return id
}

// Buy purchases auction id at its current price. The caller must send at
// least that many ugnot with the transaction; any excess is refunded
// immediately. Only a direct EOA transaction (MsgCall) may buy, so the
// payment envelope can't be spoofed via an ephemeral MsgRun realm. Returns
// the price actually paid. Crossing function.
func Buy(cur realm, id string) int64 {
	if !cur.Previous().IsUserCall() {
		panic(errNotUserCall)
	}
	buyer := cur.Previous().Address()

	a := getAuction(id)
	if a.Status != statusActive {
		panic(errNotActive)
	}

	price := priceAt(a, runtime.ChainHeight())
	sent := unsafe.OriginSend()
	paid := sent.AmountOf(denom)
	if paid < price {
		panic(errUnderpaid)
	}

	a.Status = statusSold
	a.Buyer = buyer
	a.SoldPrice = price
	totalSold++
	totalVolume += price

	bnk := banker.NewBanker(banker.BankerTypeOriginSend, cur)
	pkgAddr := cur.Address()
	if paid > price {
		bnk.SendCoins(pkgAddr, buyer, chain.NewCoins(chain.NewCoin(denom, paid-price)))
	}
	bnk.SendCoins(pkgAddr, a.Seller, chain.NewCoins(chain.NewCoin(denom, price)))

	return price
}

// Cancel withdraws an active auction. Only the seller may cancel, and only
// before it's bought. Crossing function.
func Cancel(cur realm, id string) {
	who := caller(cur)

	a := getAuction(id)
	if a.Status != statusActive {
		panic(errNotActive)
	}
	if who != a.Seller {
		panic(errNotSeller)
	}
	a.Status = statusCancelled
}

// CurrentPrice returns id's price at the current chain height.
func CurrentPrice(id string) int64 {
	return priceAt(getAuction(id), runtime.ChainHeight())
}

// AuctionInfo returns a snapshot of auction id.
func AuctionInfo(id string) (item string, seller address, status string, currentPrice int64, floorPrice int64, startPrice int64) {
	a := getAuction(id)
	return a.Item, a.Seller, a.Status.String(), priceAt(a, runtime.ChainHeight()), a.FloorPrice, a.StartPrice
}

// priceAt computes the linear-decay price of a at the given height. Once
// settled (sold or cancelled), the price is frozen: SoldPrice for a sale,
// zero for a cancellation.
func priceAt(a *auction, height int64) int64 {
	if a.Status != statusActive {
		return a.SoldPrice
	}
	elapsed := height - a.StartHeight
	if elapsed <= 0 {
		return a.StartPrice
	}
	if elapsed >= a.Duration {
		return a.FloorPrice
	}
	drop := a.StartPrice - a.FloorPrice
	return a.StartPrice - drop*elapsed/a.Duration
}

func getAuction(id string) *auction {
	v, ok := auctions.Get(id)
	if !ok {
		panic(errNotFound)
	}
	return v.(*auction)
}

// Render produces the gnoweb Markdown view: a table of every auction,
// newest first, with live prices. Not a crossing function.
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# Dutch Auction\n\n")
	b.WriteString("A price that only ever falls. List an item high; it decays block by ")
	b.WriteString("block toward a floor; the first `Buy` call wins it at whatever the ")
	b.WriteString("price is at that instant. Real ugnot, escrowed by the chain and paid ")
	b.WriteString("straight to the seller — overpayment is refunded automatically.\n\n")

	b.WriteString("- **Total listed:** " + strconv.FormatUint(totalListed, 10) + "\n")
	b.WriteString("- **Total sold:** " + strconv.FormatUint(totalSold, 10) + "\n")
	b.WriteString("- **Total volume:** " + strconv.FormatInt(totalVolume, 10) + " ugnot\n")
	b.WriteString("- **Current height:** " + strconv.FormatInt(runtime.ChainHeight(), 10) + "\n\n")

	if auctions.Size() == 0 {
		b.WriteString("_No auctions yet — call `List` to open one._\n")
		return b.String()
	}

	b.WriteString("## Auctions\n\n")
	b.WriteString("| ID | Item | Status | Price now | Floor | Start | Seller |\n")
	b.WriteString("| ---: | --- | --- | ---: | ---: | ---: | --- |\n")

	height := runtime.ChainHeight()
	ids := make([]uint64, 0, auctions.Size())
	auctions.Iterate("", "", func(key string, value any) bool {
		n, _ := strconv.ParseUint(key, 10, 64)
		ids = append(ids, n)
		return false
	})
	for i := len(ids) - 1; i >= 0; i-- {
		id := strconv.FormatUint(ids[i], 10)
		v, _ := auctions.Get(id)
		a := v.(*auction)
		b.WriteString("| " + a.ID + " | " + a.Item + " | " + a.Status.String() +
			" | " + strconv.FormatInt(priceAt(a, height), 10) +
			" | " + strconv.FormatInt(a.FloorPrice, 10) +
			" | " + strconv.FormatInt(a.StartPrice, 10) +
			" | `" + a.Seller.String() + "` |\n")
	}

	return b.String()
}
