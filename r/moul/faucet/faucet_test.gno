package faucet

import (
	"chain"
	"chain/banker"
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

const (
	zoe  = address("g12cs4cehujpffpjpywmkqj43m6u5ya53nj69sjz") // a friend with nothing
	kim  = address("g1jvh5ukk07dvd57fxefcp5aa29xaydxmxs7myyp") // a second approver
	carl = address("g1us8428u2a5satrlxzagqqa5m6vmuze025anjlj") // nobody in particular
)

func balanceOf(a address) int64 {
	return banker.NewReadonlyBanker().GetCoins(a).AmountOf(Denom)
}

// fund puts ugnot in the float the way a bank send to the realm address does,
// with no call involved. Approve spends this, so a test that funds more than
// it pays leaves a balance behind and ExampleRender sees it.
func fund(n int64) {
	testing.IssueCoins(Address(), chain.NewCoins(chain.NewCoin(Denom, n)))
}

func TestFreshFaucetIsEmptyAndOwned(t *testing.T) {
	reset()
	uassert.True(t, Owner.IsValid(), "the owner is a real address")
	uassert.True(t, Address().IsValid(), "the float address")
	uassert.True(t, zoe.IsValid())
	uassert.True(t, kim.IsValid())
	uassert.True(t, carl.IsValid())

	uassert.Equal(t, 0, Requests(), "nothing is seeded")
	uassert.Equal(t, int64(1), NextID())
	uassert.Equal(t, int64(0), TotalSent())
	uassert.Equal(t, int64(DefaultMaxPerRequest), MaxPerRequest())
	uassert.True(t, IsApprover(Owner.String()), "the owner approves by default")
	uassert.False(t, IsApprover(carl.String()))
	uassert.Equal(t, "", Status(1), "no such request")
}

// The whole point, end to end: carl asks on zoe's behalf, the owner releases
// it, and zoe (who could never have paid the gas to ask) has coins.
func TestRequestForAFriendThenApprove(cur realm, t *testing.T) {
	reset()
	urequire.Equal(t, int64(0), Balance(), "start from an empty float")
	fund(300_000_000)

	testing.SetRealm(testing.NewUserRealm(carl))
	id := Request(cross(cur), zoe.String(), 100_000_000, "no gas, needs to try the chain")
	uassert.Equal(t, int64(1), id)
	uassert.Equal(t, StatusPending, Status(id))
	uassert.Equal(t, int64(1), Pending())
	uassert.Equal(t, int64(0), balanceOf(zoe), "a request moves nothing")
	uassert.Equal(t, int64(2), NextID(), "and the next id is now readable")

	// The filer is not an approver just because they filed.
	testing.SetRealm(testing.NewUserRealm(carl))
	uassert.AbortsContains(t, cur, "is not an approver", func() {
		Approve(cross(cur), id, zoe.String(), 100_000_000)
	})

	testing.SetRealm(testing.NewUserRealm(Owner))
	Approve(cross(cur), id, zoe.String(), 100_000_000)

	uassert.Equal(t, int64(100_000_000), balanceOf(zoe), "the coins landed")
	uassert.Equal(t, int64(200_000_000), Balance(), "out of the float, not the approver")
	uassert.Equal(t, StatusSent, Status(id))
	uassert.Equal(t, int64(100_000_000), TotalSent())
	uassert.Equal(t, int64(1), SentCount())
	uassert.Equal(t, int64(0), Pending())
	uassert.Equal(t, int64(100_000_000), ReceivedBy(zoe.String()))

	// A decision happens once.
	testing.SetRealm(testing.NewUserRealm(Owner))
	uassert.AbortsContains(t, cur, "already sent", func() {
		Approve(cross(cur), id, zoe.String(), 100_000_000)
	})

	// Put the float back so ExampleRender starts from zero.
	testing.SetRealm(testing.NewUserRealm(Owner))
	Withdraw(cross(cur), Balance())
	uassert.Equal(t, int64(0), Balance())
}

// The guard that makes it safe to sign Request and Approve in the same
// transaction before either has run. The approval names an id it had to guess
// from NextID; if a different request took that id, the amounts and the
// recipient no longer agree and nothing is paid.
func TestApproveRefusesWhenTheIDMovedUnderYou(cur realm, t *testing.T) {
	reset()
	fund(500_000_000)

	// What the caller read: the next id will be 1.
	urequire.Equal(t, int64(1), NextID())

	// What actually landed at id 1: somebody else's ask, first.
	testing.SetRealm(testing.NewUserRealm(kim))
	Request(cross(cur), kim.String(), 50_000_000, "me first")
	testing.SetRealm(testing.NewUserRealm(carl))
	Request(cross(cur), zoe.String(), 100_000_000, "for zoe")

	testing.SetRealm(testing.NewUserRealm(Owner))
	uassert.AbortsContains(t, cur, "the id moved under you, nothing was paid", func() {
		Approve(cross(cur), 1, zoe.String(), 100_000_000)
	})
	uassert.Equal(t, int64(0), balanceOf(zoe), "nobody was paid")
	uassert.Equal(t, StatusPending, Status(1), "and nothing was decided")

	// The same guard catches a wrong amount at the right id.
	testing.SetRealm(testing.NewUserRealm(Owner))
	uassert.AbortsContains(t, cur, "the id moved under you, nothing was paid", func() {
		Approve(cross(cur), 2, zoe.String(), 999_000_000)
	})

	testing.SetRealm(testing.NewUserRealm(Owner))
	Approve(cross(cur), 2, zoe.String(), 100_000_000)
	uassert.Equal(t, int64(100_000_000), balanceOf(zoe))

	testing.SetRealm(testing.NewUserRealm(Owner))
	Deny(cross(cur), 1, "already funded elsewhere")
	uassert.Equal(t, StatusDenied, Status(1))
	uassert.Equal(t, int64(1), DeniedCount())
	uassert.Equal(t, int64(0), Pending())

	testing.SetRealm(testing.NewUserRealm(Owner))
	Withdraw(cross(cur), Balance())
}

func TestRequestRefusesBadInput(cur realm, t *testing.T) {
	reset()
	tests := []struct {
		name   string
		to     string
		amount int64
		reason string
		want   string
	}{
		{"not an address", "nope", 1_000_000, "hi", "is not a valid address"},
		{"zero", zoe.String(), 0, "hi", "must be a positive number"},
		{"negative", zoe.String(), -1, "hi", "must be a positive number"},
		{"over the cap", zoe.String(), DefaultMaxPerRequest + 1, "hi", "is over the per-request cap"},
		{"no reason", zoe.String(), 1_000_000, "   ", "say what it is for"},
	}
	for _, tt := range tests {
		testing.SetRealm(testing.NewUserRealm(carl))
		uassert.AbortsContains(t, cur, tt.want, func() {
			Request(cross(cur), tt.to, tt.amount, tt.reason)
		}, tt.name)
	}
	uassert.Equal(t, 0, Requests(), "none of them were filed")
	uassert.Equal(t, int64(1), NextID(), "and the id did not move")
}

func TestApproveRefusesWhatTheFloatCannotCover(cur realm, t *testing.T) {
	reset()
	fund(10_000_000)

	testing.SetRealm(testing.NewUserRealm(carl))
	id := Request(cross(cur), zoe.String(), 100_000_000, "more than is there")

	testing.SetRealm(testing.NewUserRealm(Owner))
	uassert.AbortsContains(t, cur, "float is 10000000ugnot", func() {
		Approve(cross(cur), id, zoe.String(), 100_000_000)
	})
	uassert.Equal(t, StatusPending, Status(id), "still open, the money simply is not there")

	testing.SetRealm(testing.NewUserRealm(Owner))
	Withdraw(cross(cur), Balance())
}

func TestOnlyTheOwnerChangesWhoApproves(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(carl))
	uassert.AbortsContains(t, cur, "owner only", func() {
		AddApprover(cross(cur), carl.String())
	})

	testing.SetRealm(testing.NewUserRealm(Owner))
	AddApprover(cross(cur), kim.String())
	uassert.True(t, IsApprover(kim.String()))

	// A second approver can decide, but cannot widen the roster.
	fund(200_000_000)
	testing.SetRealm(testing.NewUserRealm(carl))
	id := Request(cross(cur), zoe.String(), 50_000_000, "kim vouches")
	testing.SetRealm(testing.NewUserRealm(kim))
	Approve(cross(cur), id, zoe.String(), 50_000_000)
	uassert.Equal(t, StatusSent, Status(id))

	testing.SetRealm(testing.NewUserRealm(kim))
	uassert.AbortsContains(t, cur, "owner only", func() {
		AddApprover(cross(cur), carl.String())
	})

	// The owner is the one approver that cannot be removed: a faucet with no
	// approver is a faucet with a locked float.
	testing.SetRealm(testing.NewUserRealm(Owner))
	uassert.AbortsContains(t, cur, "the owner is always an approver", func() {
		RemoveApprover(cross(cur), Owner.String())
	})
	testing.SetRealm(testing.NewUserRealm(Owner))
	RemoveApprover(cross(cur), kim.String())
	uassert.False(t, IsApprover(kim.String()))

	testing.SetRealm(testing.NewUserRealm(Owner))
	Withdraw(cross(cur), Balance())
}

func TestFundAndWithdrawAreOwnerReversible(cur realm, t *testing.T) {
	reset()
	fund(400_000_000)
	testing.SetOriginSend(chain.NewCoins(chain.NewCoin(Denom, 400_000_000)))
	testing.SetRealm(testing.NewUserRealm(kim))
	Fund(cross(cur))
	uassert.Equal(t, int64(400_000_000), Balance())

	testing.SetRealm(testing.NewUserRealm(kim))
	uassert.AbortsContains(t, cur, "owner only", func() {
		Withdraw(cross(cur), 1)
	})

	testing.SetRealm(testing.NewUserRealm(Owner))
	uassert.AbortsContains(t, cur, "float is 400000000ugnot", func() {
		Withdraw(cross(cur), 400_000_001)
	})

	before := balanceOf(Owner)
	testing.SetRealm(testing.NewUserRealm(Owner))
	Withdraw(cross(cur), 400_000_000)
	uassert.Equal(t, int64(0), Balance())
	uassert.Equal(t, before+400_000_000, balanceOf(Owner))
}

func TestSetMaxPerRequest(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(carl))
	uassert.AbortsContains(t, cur, "owner only", func() {
		SetMaxPerRequest(cross(cur), 1)
	})

	testing.SetRealm(testing.NewUserRealm(Owner))
	SetMaxPerRequest(cross(cur), 1_000_000_000)
	uassert.Equal(t, int64(1_000_000_000), MaxPerRequest())

	testing.SetRealm(testing.NewUserRealm(carl))
	id := Request(cross(cur), zoe.String(), 900_000_000, "over the old cap, under the new one")
	uassert.Equal(t, StatusPending, Status(id))
}

// A reason is arbitrary text from an arbitrary account, and this realm's path
// is permanent, so the escaping has to be right before it ships. Assert the
// dangerous SEQUENCES are dead on the page, not that some particular escape
// was chosen.
func TestRenderEscapesTheReason(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(carl))
	id := Request(cross(cur), zoe.String(), 1_000_000,
		"[click](https://evil.example) ![b](https://evil.example/p.png) <gno-columns>")

	for _, page := range []string{Render(""), Render("req/" + "1")} {
		uassert.False(t, contains(page, "](https://evil.example"), "no live link")
		uassert.False(t, contains(page, "![b]"), "no image beacon")
		uassert.False(t, contains(page, "<gno-columns>"), "no gnoweb chrome")
		uassert.True(t, contains(page, "click"), "the readable text survives")
	}
	uassert.Equal(t, StatusPending, Status(id))
}

func contains(haystack, needle string) bool {
	for i := 0; i+len(needle) <= len(haystack); i++ {
		if haystack[i:i+len(needle)] == needle {
			return true
		}
	}
	return false
}

func TestGnotFormatting(t *testing.T) {
	tests := []struct {
		in   int64
		want string
	}{
		{0, "0"},
		{1, "0.000001"},
		{1_500_000, "1.5"},
		{100_000_000, "100"},
		{5_000_000_000, "5000"},
		{-2_500_000, "-2.5"},
	}
	for _, tt := range tests {
		uassert.Equal(t, tt.want, gnot(tt.in))
	}
}

func TestReqPath(t *testing.T) {
	tests := []struct {
		in   string
		id   int64
		want bool
	}{
		{"", 0, false},
		{"req/1", 1, true},
		{"req/42", 42, true},
		{"req/0", 0, false},
		{"req/x", 0, false},
		{"req/", 0, false},
		{"other", 0, false},
	}
	for _, tt := range tests {
		id, ok := reqPath(tt.in)
		uassert.Equal(t, tt.want, ok, tt.in)
		uassert.Equal(t, tt.id, id, tt.in)
	}
}
