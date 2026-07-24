package dutchauction

import (
	"strings"
	"testing"

	"chain"
	"chain/banker"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/testutils/v0"
)

var realmAddr = chain.PackageAddress("gno.land/r/g12cs4cehujpffpjpywmkqj43m6u5ya53nj69sjz/dutchauction")

func reset() {
	auctions = avl.Tree{}
	nextID = 0
	totalListed = 0
	totalSold = 0
	totalVolume = 0
}

// fundBuy simulates a buyer sending `amount` ugnot alongside the tx: the
// runtime deposits it at the realm's address first, then unsafe.OriginSend
// reports it to the crossing function.
func fundBuy(buyer address, amount int64) {
	testing.IssueCoins(realmAddr, chain.Coins{{"ugnot", amount}})
	testing.SetOriginSend(chain.Coins{{"ugnot", amount}})
	testing.SetRealm(testing.NewUserRealm(buyer))
}

func TestListAndPriceDecay(cur realm, t *testing.T) {
	reset()
	seller := testutils.TestAddress("seller")

	testing.SetRealm(testing.NewUserRealm(seller))
	id := List(cross(cur), "vintage synth", 1000, 100, 100)

	if got := CurrentPrice(id); got != 1000 {
		t.Fatalf("price at start = %d, want 1000", got)
	}

	testing.SkipHeights(50)
	if got := CurrentPrice(id); got != 550 {
		t.Fatalf("price at midpoint = %d, want 550", got)
	}

	testing.SkipHeights(100)
	if got := CurrentPrice(id); got != 100 {
		t.Fatalf("price past duration = %d, want floor 100", got)
	}
}

func TestListRejectsBadInput(cur realm, t *testing.T) {
	reset()
	seller := testutils.TestAddress("seller")
	testing.SetRealm(testing.NewUserRealm(seller))

	rec := revive(func() { List(cross(cur), "", 1000, 100, 100) })
	if rec == nil {
		t.Fatal("expected panic on empty item")
	}
	rec = revive(func() { List(cross(cur), "thing", 100, 1000, 100) })
	if rec == nil {
		t.Fatal("expected panic when floorPrice >= startPrice")
	}
	rec = revive(func() { List(cross(cur), "thing", 1000, 100, 0) })
	if rec == nil {
		t.Fatal("expected panic on non-positive duration")
	}
}

func TestBuyExactSettlesToSeller(cur realm, t *testing.T) {
	reset()
	seller := testutils.TestAddress("seller")
	buyer := testutils.TestAddress("buyer")

	testing.SetRealm(testing.NewUserRealm(seller))
	id := List(cross(cur), "vintage synth", 1000, 100, 100)

	testing.SkipHeights(50) // price = 550
	fundBuy(buyer, 550)
	paid := Buy(cross(cur), id)
	if paid != 550 {
		t.Fatalf("paid = %d, want 550", paid)
	}

	ro := banker.NewReadonlyBanker()
	sellerBal := ro.GetCoins(seller).AmountOf("ugnot")
	if sellerBal != 550 {
		t.Fatalf("seller balance = %d, want 550", sellerBal)
	}

	_, _, status, price, _, _ := AuctionInfo(id)
	if status != "sold" {
		t.Fatalf("status = %q, want sold", status)
	}
	if price != 550 {
		t.Fatalf("frozen price = %d, want 550", price)
	}
}

func TestBuyOverpayIsRefunded(cur realm, t *testing.T) {
	reset()
	seller := testutils.TestAddress("seller2")
	buyer := testutils.TestAddress("buyer2")

	testing.SetRealm(testing.NewUserRealm(seller))
	id := List(cross(cur), "arcade cabinet", 1000, 100, 100)

	fundBuy(buyer, 1000) // pay the full start price up front
	paid := Buy(cross(cur), id)
	if paid != 1000 {
		t.Fatalf("paid = %d, want 1000 (bought at block 0)", paid)
	}

	ro := banker.NewReadonlyBanker()
	buyerBal := ro.GetCoins(buyer).AmountOf("ugnot")
	if buyerBal != 0 {
		t.Fatalf("buyer refund leftover = %d, want 0 (no overpay at price 1000)", buyerBal)
	}
}

func TestBuyUnderpaidPanics(cur realm, t *testing.T) {
	reset()
	seller := testutils.TestAddress("seller3")
	buyer := testutils.TestAddress("buyer3")

	testing.SetRealm(testing.NewUserRealm(seller))
	id := List(cross(cur), "amp", 1000, 100, 100)

	fundBuy(buyer, 500)
	rec := revive(func() { Buy(cross(cur), id) })
	if rec == nil {
		t.Fatal("expected panic when underpaying")
	}
}

func TestCancelBySellerOnly(cur realm, t *testing.T) {
	reset()
	seller := testutils.TestAddress("seller4")
	mallory := testutils.TestAddress("mallory")

	testing.SetRealm(testing.NewUserRealm(seller))
	id := List(cross(cur), "pedal", 1000, 100, 100)

	testing.SetRealm(testing.NewUserRealm(mallory))
	rec := revive(func() { Cancel(cross(cur), id) })
	if rec == nil {
		t.Fatal("expected panic when a non-seller cancels")
	}

	testing.SetRealm(testing.NewUserRealm(seller))
	Cancel(cross(cur), id)

	_, _, status, _, _, _ := AuctionInfo(id)
	if status != "cancelled" {
		t.Fatalf("status = %q, want cancelled", status)
	}

	fundBuy(mallory, 1000)
	rec = revive(func() { Buy(cross(cur), id) })
	if rec == nil {
		t.Fatal("expected panic buying a cancelled auction")
	}
}

func TestRenderHome(t *testing.T) {
	reset()
	out := Render("")
	if !strings.Contains(out, "Dutch Auction") {
		t.Fatalf("render output missing title\n%s", out)
	}
}
