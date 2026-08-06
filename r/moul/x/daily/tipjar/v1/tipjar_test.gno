package tipjar

import (
	"strings"
	"testing"

	"chain"
	"chain/banker"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/testutils/v0"
)

var realmAddr = chain.PackageAddress("gno.land/r/g12cs4cehujpffpjpywmkqj43m6u5ya53nj69sjz/tipjar")

// reset clears package globals between tests, pinning owner to a known test
// address rather than whatever init() captured from the test harness.
func reset() {
	owner = testutils.TestAddress("owner")
	tippers = avl.Tree{}
	recent = nil
	totalReceived = 0
	withdrawn = 0
	tipCount = 0
}

// fund simulates a tipper sending `amount` ugnot alongside the tx: the
// runtime deposits it at the realm's address first, then unsafe.OriginSend
// reports it to the crossing function. SetRealm is call-frame scoped (see
// build.md), so the caller must still SetRealm directly before crossing.
func fund(amount int64) {
	testing.IssueCoins(realmAddr, chain.Coins{{denom, amount}})
	testing.SetOriginSend(chain.Coins{{denom, amount}})
}

func TestTipCreditsAndTracks(cur realm, t *testing.T) {
	reset()
	alice := testutils.TestAddress("alice")

	fund(500)
	testing.SetRealm(testing.NewUserRealm(alice))
	Tip(cross(cur), "gm")

	if got := Balance(); got != 500 {
		t.Fatalf("Balance() = %d, want 500", got)
	}
	if tipCount != 1 {
		t.Fatalf("tipCount = %d, want 1", tipCount)
	}
	ts := get(alice)
	if ts.total != 500 || ts.count != 1 || ts.lastMessage != "gm" {
		t.Fatalf("unexpected tipper stats: %+v", ts)
	}

	fund(250)
	testing.SetRealm(testing.NewUserRealm(alice))
	Tip(cross(cur), "again")
	if got := get(alice).total; got != 750 {
		t.Fatalf("cumulative total = %d, want 750", got)
	}
	if got := Balance(); got != 750 {
		t.Fatalf("Balance() after second tip = %d, want 750", got)
	}
}

func TestTipRejectsZeroAmount(cur realm, t *testing.T) {
	reset()
	alice := testutils.TestAddress("alice")
	testing.SetRealm(testing.NewUserRealm(alice))

	rec := revive(func() { Tip(cross(cur), "freeloading") })
	if rec == nil {
		t.Fatal("expected panic when tipping with no ugnot sent")
	}
}

func TestTipRejectsNonUserCall(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewCodeRealm("gno.land/r/g1attacker/relay"))

	rec := revive(func() { Tip(cross(cur), "sneaky") })
	if rec == nil {
		t.Fatal("expected panic when the caller isn't an EOA via MsgCall")
	}
}

func TestWithdrawOwnerOnly(cur realm, t *testing.T) {
	reset()
	alice := testutils.TestAddress("alice")
	mallory := testutils.TestAddress("mallory")

	fund(1000)
	testing.SetRealm(testing.NewUserRealm(alice))
	Tip(cross(cur), "for the jar")

	testing.SetRealm(testing.NewUserRealm(mallory))
	rec := revive(func() { Withdraw(cross(cur), 100) })
	if rec == nil {
		t.Fatal("expected panic when a non-owner withdraws")
	}

	testing.SetRealm(testing.NewUserRealm(owner))
	Withdraw(cross(cur), 400)

	if got := Balance(); got != 600 {
		t.Fatalf("Balance() after withdraw = %d, want 600", got)
	}
	ro := banker.NewReadonlyBanker()
	if got := ro.GetCoins(owner).AmountOf(denom); got != 400 {
		t.Fatalf("owner received = %d, want 400", got)
	}

	rec = revive(func() { Withdraw(cross(cur), 10000) })
	if rec == nil {
		t.Fatal("expected panic when withdrawing more than the balance")
	}
}

func TestRenderShowsLeaderboardAndFeed(cur realm, t *testing.T) {
	reset()
	if !strings.Contains(Render(""), "No tips yet") {
		t.Fatal("expected empty-jar placeholder")
	}

	alice := testutils.TestAddress("alice")
	fund(300)
	testing.SetRealm(testing.NewUserRealm(alice))
	Tip(cross(cur), "nice work")

	out := Render("")
	if !strings.Contains(out, "Leaderboard") {
		t.Fatal("expected leaderboard section")
	}
	if !strings.Contains(out, "nice work") {
		t.Fatal("expected the tip message in the recent-tips feed")
	}
}
