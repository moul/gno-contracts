package moultest

import (
	"chain"
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

// testing.SetRealm governs only the crossing calls made from the frame that
// called it, so every account switch below is written inline in the test body
// rather than in a helper.

func TestDenom(t *testing.T) {
	// The denom is what a wallet, an explorer and a -send flag all type, and it
	// is immutable once the first coin exists. Pin the literal: deriving it from
	// Path would restate the code rather than check it.
	uassert.Equal(t, "/gno.land/r/moul/x/moultest/v0:moultest", Denom)
}

func TestClaimIssuesRealCoins(cur realm, t *testing.T) {
	alice := testutils.TestAddress("mt-alice")
	testing.SetRealm(testing.NewUserRealm(alice))

	_, ever := NextClaim(alice)
	uassert.False(t, ever, "no claim recorded before the first one")
	uassert.Equal(t, int64(0), BalanceOf(alice))

	before := Circulating()
	got := Claim(cross(cur))

	uassert.Equal(t, ClaimAmount, got)
	// The balance comes from the bank, not from realm storage: nothing in this
	// realm records who holds what.
	uassert.Equal(t, ClaimAmount, BalanceOf(alice))
	uassert.Equal(t, before+ClaimAmount, Circulating())
	uassert.Equal(t, ClaimAmount, ClaimedBy(alice))

	next, ever := NextClaim(alice)
	uassert.True(t, ever, "a cooldown is recorded")
	uassert.Equal(t, ClaimEvery, next-123, "first test block is 123, so the cooldown lands there")
}

func TestClaimCooldown(cur realm, t *testing.T) {
	bob := testutils.TestAddress("mt-bob")
	testing.SetRealm(testing.NewUserRealm(bob))

	Claim(cross(cur))
	uassert.AbortsContains(t, cur, "too soon", func() { Claim(cross(cur)) })

	testing.SkipHeights(ClaimEvery - 1)
	uassert.AbortsContains(t, cur, "too soon", func() { Claim(cross(cur)) })

	testing.SkipHeights(1)
	Claim(cross(cur))
	uassert.Equal(t, 2*ClaimAmount, BalanceOf(bob))
}

func TestAccountCap(cur realm, t *testing.T) {
	carol := testutils.TestAddress("mt-carol")
	testing.SetRealm(testing.NewUserRealm(carol))

	for ClaimedBy(carol)+ClaimAmount <= MaxPerAccount {
		Claim(cross(cur))
		testing.SkipHeights(ClaimEvery)
	}
	uassert.Equal(t, MaxPerAccount, ClaimedBy(carol))
	uassert.AbortsContains(t, cur, "account cap reached", func() { Claim(cross(cur)) })

	// Waiting does not help: the cooldown is not what stopped it.
	testing.SkipHeights(ClaimEvery * 10)
	uassert.AbortsContains(t, cur, "account cap reached", func() { Claim(cross(cur)) })
}

func TestBurnIsScopedToTheCaller(cur realm, t *testing.T) {
	dave := testutils.TestAddress("mt-dave")
	erin := testutils.TestAddress("mt-erin")

	testing.SetRealm(testing.NewUserRealm(erin))
	Claim(cross(cur))
	erinBefore := BalanceOf(erin)

	testing.SetRealm(testing.NewUserRealm(dave))
	Claim(cross(cur))

	issuedBefore, burnedBefore, circBefore := Issued(), Burned(), Circulating()
	claimedBefore := ClaimedBy(dave)

	Burn(cross(cur), 400)

	uassert.Equal(t, ClaimAmount-400, BalanceOf(dave))
	uassert.Equal(t, circBefore-400, Circulating(), "burning destroys the coin, it is not moved")
	uassert.Equal(t, burnedBefore+400, Burned())
	// Issuance is monotonic on purpose: if burning gave cap headroom back,
	// claim-burn-claim would be an unlimited faucet.
	uassert.Equal(t, issuedBefore, Issued())
	uassert.Equal(t, claimedBefore, ClaimedBy(dave))
	// Burn takes no address, so erin cannot be reached from dave's call.
	uassert.Equal(t, erinBefore, BalanceOf(erin))

	uassert.AbortsContains(t, cur, "cannot burn", func() { Burn(cross(cur), 1_000_000) })
	uassert.AbortsContains(t, cur, "positive amount", func() { Burn(cross(cur), 0) })
	uassert.AbortsContains(t, cur, "positive amount", func() { Burn(cross(cur), -5) })
}

func TestTipRidesTheEnvelope(cur realm, t *testing.T) {
	frank := testutils.TestAddress("mt-frank")
	grace := testutils.TestAddress("mt-grace")

	// On chain the -send envelope is credited to this realm's address before
	// the function runs. The test harness has no bank-send primitive, so the
	// credit is issued directly here; SetOriginSend is what the banker checks
	// against, and it is the half that bounds what Tip may spend.
	realmAddr := chain.PackageAddress(Path)
	envelope := chain.NewCoins(chain.NewCoin(Denom, 250))
	testing.IssueCoins(realmAddr, envelope)
	// Unrelated coins already sitting at the realm's address. A RealmSend
	// banker could spend these; the OriginSend one may not, and that is the
	// property being pinned.
	testing.IssueCoins(realmAddr, chain.NewCoins(chain.NewCoin(Denom, 5_000)))
	realmBefore := BalanceOf(realmAddr)

	testing.SetRealm(testing.NewUserRealm(frank))
	testing.SetOriginSend(envelope)
	sent := Tip(cross(cur), grace, "nice work")

	uassert.Equal(t, int64(250), sent)
	uassert.Equal(t, int64(250), BalanceOf(grace), "the tip landed on the recipient")
	uassert.Equal(t, realmBefore-250, BalanceOf(realmAddr),
		"exactly the envelope left the realm, and nothing else it was holding")
	uassert.Equal(t, 1, len(tips))
	uassert.Equal(t, "nice work", tips[0].note)

	testing.SetOriginSend(nil)
}

func TestTipRefusals(cur realm, t *testing.T) {
	heidi := testutils.TestAddress("mt-heidi")
	ivan := testutils.TestAddress("mt-ivan")

	testing.SetRealm(testing.NewUserRealm(heidi))
	testing.SetOriginSend(nil)
	uassert.AbortsContains(t, cur, "attach moultest", func() { Tip(cross(cur), ivan, "hi") })

	envelope := chain.NewCoins(chain.NewCoin(Denom, 10))
	testing.IssueCoins(chain.PackageAddress(Path), envelope)
	testing.SetOriginSend(envelope)
	uassert.AbortsContains(t, cur, "tip somebody else", func() { Tip(cross(cur), heidi, "me") })
	uassert.AbortsContains(t, cur, "valid address", func() { Tip(cross(cur), "nope", "hi") })
	uassert.AbortsContains(t, cur, "note is", func() {
		Tip(cross(cur), ivan, strings.Repeat("x", MaxNote+1))
	})

	testing.SetOriginSend(nil)
}

func TestSupplyCap(cur realm, t *testing.T) {
	// Fill the remaining supply with fresh accounts, each capped at
	// MaxPerAccount, then check that the next one is refused. Issuance carries
	// across tests, so the loop starts from whatever is left rather than from
	// MaxSupply.
	names := []string{"cap-a", "cap-b", "cap-c", "cap-d", "cap-e", "cap-f",
		"cap-g", "cap-h", "cap-i", "cap-j", "cap-k", "cap-l"}
	for _, name := range names {
		if Issued()+ClaimAmount > MaxSupply {
			break
		}
		who := testutils.TestAddress(name)
		testing.SetRealm(testing.NewUserRealm(who))
		for ClaimedBy(who)+ClaimAmount <= MaxPerAccount && Issued()+ClaimAmount <= MaxSupply {
			Claim(cross(cur))
			testing.SkipHeights(ClaimEvery)
		}
	}
	uassert.Equal(t, MaxSupply, Issued(), "the accounts above exhaust the supply exactly")

	late := testutils.TestAddress("cap-late")
	testing.SetRealm(testing.NewUserRealm(late))
	uassert.AbortsContains(t, cur, "supply cap reached", func() { Claim(cross(cur)) })

	// Burning does not reopen the faucet either: circulating drops, issued does
	// not, and the cap is on issued.
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("cap-a")))
	Burn(cross(cur), 500)
	uassert.Equal(t, MaxSupply, Issued())
	testing.SetRealm(testing.NewUserRealm(late))
	uassert.AbortsContains(t, cur, "supply cap reached", func() { Claim(cross(cur)) })
}

func TestRender(t *testing.T) {
	index := Render("")
	uassert.True(t, strings.Contains(index, "# moultest"), "heading:\n"+index)
	uassert.True(t, strings.Contains(index, Denom), "the denom is on the page")
	uassert.True(t, strings.Contains(index, "| issued, ever |"), "supply table:\n"+index)
	uassert.True(t, strings.Contains(index, "nice work"), "the tip board is shown:\n"+index)

	frank := testutils.TestAddress("mt-frank")
	acct := Render(frank.String())
	uassert.True(t, strings.Contains(acct, frank.String()), "the account section names it:\n"+acct)
	uassert.True(t, strings.Contains(acct, "claimed for life"), acct)

	// A path that is not an address renders the index without an account block.
	uassert.False(t, strings.Contains(Render("not-an-address"), "claimed for life"),
		"a junk path adds no account section")
}
