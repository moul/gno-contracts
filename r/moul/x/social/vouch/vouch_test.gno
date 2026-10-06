package vouch

import (
	"strings"
	"testing"

	"chain"
	"chain/banker"

	vo "gno.land/p/moul/x/social/vouch/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

var (
	alice = testutils.TestAddress("alice")
	bob   = testutils.TestAddress("bob")
	carol = testutils.TestAddress("carol")

	realmAddr = chain.PackageAddress(realmPath)
)

// reset clears realm state. Realm globals live for the whole test binary, so
// every test that reads a score, a bond or a refund starts here.
func reset() { graph = vo.NewGraph() }

// fund simulates the coins attached to the next call: the runtime credits the
// realm's address first, and the crossing function then reads the envelope off
// the transaction. fund(0) clears it, which is the ordinary unbonded case.
//
// testing.SetRealm is call-frame scoped, so the caller still switches account
// inline in the test body right before crossing.
func fund(amount int64) {
	if amount <= 0 {
		testing.SetOriginSend(chain.Coins{})
		return
	}
	testing.IssueCoins(realmAddr, chain.Coins{{denom, amount}})
	testing.SetOriginSend(chain.Coins{{denom, amount}})
}

func balanceOf(addr address) int64 {
	return banker.NewReadonlyBanker().GetCoins(addr).AmountOf(denom)
}

// The score counts people, which is the property every caller of IsTrusted
// depends on: a repeated vouch does not raise it, a revoke lowers it.
func TestScoreCountsPeopleAndNotVouches(cur realm, t *testing.T) {
	reset()

	fund(0)
	testing.SetRealm(testing.NewUserRealm(bob))
	Vouch(cross(cur), alice, "worked with them for two years")
	uassert.Equal(t, 1, ScoreOf(alice))

	fund(0)
	testing.SetRealm(testing.NewUserRealm(bob))
	Vouch(cross(cur), alice, "still true")
	uassert.Equal(t, 1, ScoreOf(alice), "one person is one point, however often they say it")
	uassert.Equal(t, "still true", ReasonFrom(bob, alice), "the reason was updated")
	uassert.Equal(t, 1, Count())

	fund(0)
	testing.SetRealm(testing.NewUserRealm(carol))
	Vouch(cross(cur), alice, "we shipped together")
	uassert.Equal(t, 2, ScoreOf(alice))
	uassert.Equal(t, 1, People(), "one address has been vouched for")

	fund(0)
	testing.SetRealm(testing.NewUserRealm(carol))
	Revoke(cross(cur), alice)
	uassert.Equal(t, 1, ScoreOf(alice), "revoking lowers the score")
	uassert.Equal(t, 1, Count())
}

func TestVouchRefusals(cur realm, t *testing.T) {
	reset()

	fund(0)
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "cannot vouch for itself", func() {
		Vouch(cross(cur), alice, "I am great")
	})

	fund(0)
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "reason is empty", func() {
		Vouch(cross(cur), bob, "   ")
	})

	fund(0)
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "reason is empty", func() {
		Vouch(cross(cur), bob, "one line\nonly")
	})

	fund(0)
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "no such vouch", func() {
		Revoke(cross(cur), bob)
	})

	fund(0)
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "nothing to withdraw", func() {
		Withdraw(cross(cur))
	})

	uassert.Equal(t, 0, Count())
}

// The bond follows the vouch in both directions, and the coins only move on
// Withdraw. Balances are asserted here because the bank does not carry over
// between test functions.
func TestTheBondIsLockedUntilTheVouchIsRevoked(cur realm, t *testing.T) {
	reset()
	before := balanceOf(bob)

	fund(1_000_000)
	testing.SetRealm(testing.NewUserRealm(bob))
	Vouch(cross(cur), alice, "1 GNOT says this is a real person")
	uassert.Equal(t, int64(1_000_000), BondedFor(alice))
	uassert.Equal(t, int64(1_000_000), TotalBonded())
	uassert.Equal(t, int64(0), Owed(bob), "nothing is owed while the vouch stands")

	// Vouching again adds to the bond rather than replacing it.
	fund(500_000)
	testing.SetRealm(testing.NewUserRealm(bob))
	Vouch(cross(cur), alice, "doubling down")
	uassert.Equal(t, int64(1_500_000), BondedFor(alice))
	uassert.Equal(t, int64(1_500_000), BondFrom(bob, alice))

	// Revoking moves the bond to the ledger and nothing else.
	fund(0)
	testing.SetRealm(testing.NewUserRealm(bob))
	refund := Revoke(cross(cur), alice)
	uassert.Equal(t, int64(1_500_000), refund)
	uassert.Equal(t, int64(0), BondedFor(alice))
	uassert.Equal(t, int64(1_500_000), Owed(bob))
	uassert.Equal(t, int64(1_500_000), TotalOwed())
	uassert.Equal(t, before, balanceOf(bob), "revoking sends nothing")

	// Withdrawing is what moves the coins, once.
	fund(0)
	testing.SetRealm(testing.NewUserRealm(bob))
	got := Withdraw(cross(cur))
	uassert.Equal(t, int64(1_500_000), got)
	uassert.Equal(t, before+1_500_000, balanceOf(bob), "the bond came back")
	uassert.Equal(t, int64(0), Owed(bob))
	uassert.Equal(t, int64(0), TotalOwed())

	fund(0)
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "nothing to withdraw", func() {
		Withdraw(cross(cur))
	})
	uassert.Equal(t, before+1_500_000, balanceOf(bob), "and only once")
}

// A bond belongs to whoever posted it, not to whoever it was posted on.
func TestOnlyTheVoucherGetsTheBondBack(cur realm, t *testing.T) {
	reset()

	fund(700_000)
	testing.SetRealm(testing.NewUserRealm(bob))
	Vouch(cross(cur), alice, "my money, my claim")

	fund(0)
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "no such vouch", func() {
		Revoke(cross(cur), bob)
	})

	fund(0)
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "nothing to withdraw", func() {
		Withdraw(cross(cur))
	})
	uassert.Equal(t, int64(700_000), BondedFor(alice), "the bond is untouched")
}

func TestIsTrustedIsTheGate(cur realm, t *testing.T) {
	reset()

	uassert.False(t, IsTrusted(alice, 1), "nobody starts trusted")
	uassert.False(t, IsTrusted(alice, 0), "a zero min does not open the gate for nobody")

	fund(0)
	testing.SetRealm(testing.NewUserRealm(bob))
	Vouch(cross(cur), alice, "one")
	uassert.True(t, IsTrusted(alice, 1))
	uassert.False(t, IsTrusted(alice, 2))

	fund(0)
	testing.SetRealm(testing.NewUserRealm(carol))
	Vouch(cross(cur), alice, "two")
	uassert.True(t, IsTrusted(alice, 2))
	uassert.False(t, IsTrusted(alice, 3))

	// The cheapest sybil shape, and the reason a real gate asks for two.
	fund(0)
	testing.SetRealm(testing.NewUserRealm(alice))
	Vouch(cross(cur), bob, "back at you")
	uassert.True(t, Mutual(alice, bob))
	uassert.True(t, IsTrusted(bob, 1), "a mutual pair passes a gate set at one")
	uassert.False(t, IsTrusted(bob, 2))
}

func TestTheTwoDirections(cur realm, t *testing.T) {
	reset()

	fund(0)
	testing.SetRealm(testing.NewUserRealm(alice))
	Vouch(cross(cur), bob, "a to b")
	fund(0)
	testing.SetRealm(testing.NewUserRealm(alice))
	Vouch(cross(cur), carol, "a to c")
	fund(0)
	testing.SetRealm(testing.NewUserRealm(bob))
	Vouch(cross(cur), carol, "b to c")

	uassert.Equal(t, 2, len(VouchesOf(alice)))
	uassert.Equal(t, 0, len(VouchedBy(alice)))
	uassert.Equal(t, 2, len(VouchedBy(carol)))
	uassert.Equal(t, 0, len(VouchesOf(carol)))
	uassert.Equal(t, "b to c", ReasonFrom(bob, carol))
	uassert.Equal(t, "", ReasonFrom(carol, bob))
	uassert.Equal(t, int64(0), BondFrom(alice, bob), "an unbonded vouch is worth nothing")
}

// Badge is a borrowed read: a host realm calls it with no realm token and
// gets a line pointing back at this realm's page.
func TestBadge(cur realm, t *testing.T) {
	reset()
	uassert.True(t, strings.Contains(Badge(alice), "not vouched for"))

	fund(2_000_000)
	testing.SetRealm(testing.NewUserRealm(bob))
	Vouch(cross(cur), alice, "one")

	got := Badge(alice)
	uassert.True(t, strings.Contains(got, "1 voucher]"), got)
	uassert.True(t, strings.Contains(got, "2 GNOT bonded"), got)
	uassert.True(t, strings.Contains(got, "/r/moul/x/social/vouch/v0:addr/"+alice.String()), got)
}

// TestRender uses uassert rather than an Example because every view contains
// consecutive blank lines, which gno collapses inside an // Output: block.
func TestRender(cur realm, t *testing.T) {
	reset()

	fund(3_000_000)
	testing.SetRealm(testing.NewUserRealm(bob))
	Vouch(cross(cur), alice, "a reason with [a link](x) and a | pipe")
	fund(0)
	testing.SetRealm(testing.NewUserRealm(carol))
	Vouch(cross(cur), alice, "second voucher")

	index := Render("")
	uassert.True(t, strings.Contains(index, "| 2 | 1 | 3 GNOT | 0 GNOT |"),
		"vouches, people, bonded, owed: "+index)
	uassert.True(t, strings.Contains(index, `import "`+realmPath+`"`), "the index is the gate doc")
	uassert.True(t, strings.Contains(index, "func=Vouch"), "the index offers the transaction")
	uassert.True(t, strings.Contains(index, "\U0001F947"), "the board has a podium: "+index)

	page := Render("addr/" + alice.String())
	uassert.True(t, strings.Contains(page, alice.String()), "the page names the address")
	uassert.True(t, strings.Contains(page, "a reason with \\[a link\\]\\(x\\) and a \\| pipe"),
		"the reason is escaped where it is shown: "+page)
	uassert.True(t, strings.Contains(page, "func=Revoke"))

	// The other direction of the same edge, from the voucher's page.
	vouchers := Render("addr/" + bob.String())
	uassert.True(t, strings.Contains(vouchers, "This address vouches for nobody.") == false,
		"bob vouches for alice: "+vouchers)
	uassert.True(t, strings.Contains(vouchers, "Nobody vouches for this address."))

	uassert.Equal(t, "# Vouch\nNot an address: nope", Render("addr/nope"))
	uassert.True(t, strings.HasPrefix(Render("elsewhere"), "# Not found"))

	// An empty graph says so rather than rendering an empty table.
	reset()
	uassert.True(t, strings.Contains(Render(""), "Nobody has been vouched for yet."))
}

func TestRenderOfAnUnknownAddress(cur realm, t *testing.T) {
	reset()
	page := Render("addr/" + carol.String())
	uassert.True(t, strings.Contains(page, "Nobody vouches for this address."), page)
	uassert.True(t, strings.Contains(page, "This address vouches for nobody."), page)
	uassert.True(t, strings.Contains(page, "| 0 | 0 GNOT | no | 0 GNOT |"), page)
}
