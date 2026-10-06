package curated

import (
	"strings"
	"testing"

	"chain"
	"chain/banker"
	"chain/runtime"

	cu "gno.land/p/moul/x/social/curated/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

var realmAddr = chain.PackageAddress(realmPath)

var (
	alice = testutils.TestAddress("alice")
	bob   = testutils.TestAddress("bob")
	carol = testutils.TestAddress("carol")
	dave  = testutils.TestAddress("dave")
)

// reset clears realm state. Realm globals live for the whole test binary, so
// every entry, challenge and credit a later test reads starts here. The BANK
// does not carry over the same way, which is why every balance is asserted in
// the test that issued it.
func reset() {
	list = cu.New(Deposit, ChallengeBlocks)
}

// pay credits the realm the way a real transaction would: the runtime deposits
// the envelope at the realm's address, then OriginSend reports it to the
// crossing function.
func pay(amount int64) {
	testing.IssueCoins(realmAddr, chain.Coins{{Denom, amount}})
	testing.SetOriginSend(chain.Coins{{Denom, amount}})
}

// apply lists an entry as who. It crosses immediately after SetRealm, which is
// what makes the account switch take: a helper that sets the realm and does
// not itself cross is silently ignored.
func apply(cur realm, who address, key, url, description string) {
	pay(Deposit)
	testing.SetRealm(testing.NewUserRealm(who))
	Apply(cross(cur), key, url, description)
}

// challenge objects to an entry as who, bonding what that entry's deposit was.
func challenge(cur realm, who address, key string) {
	_, _, _, bond, _, _ := Get(key)
	pay(bond)
	testing.SetRealm(testing.NewUserRealm(who))
	Challenge(cross(cur), key)
}

// balance is what addr holds on chain right now.
func balance(addr address) int64 {
	return banker.NewReadonlyBanker().GetCoins(addr).AmountOf(Denom)
}

func TestApplyTakesExactlyTheDepositAndListsAtOnce(cur realm, t *testing.T) {
	reset()

	// Underpaying and overpaying are both refused: a realm that silently kept
	// the excess would have invented a fee nobody agreed to.
	pay(Deposit - 1)
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "costs exactly", func() {
		Apply(cross(cur), "gnoswap", "https://gnoswap.io", "an AMM")
	})
	pay(Deposit + 1)
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "costs exactly", func() {
		Apply(cross(cur), "gnoswap", "https://gnoswap.io", "an AMM")
	})
	uassert.Equal(t, 0, Count())

	apply(cur, alice, "gnoswap", "https://gnoswap.io", "an AMM on gno.land")

	url, description, owner, deposit, at, state := Get("gnoswap")
	uassert.Equal(t, "https://gnoswap.io", url)
	uassert.Equal(t, "an AMM on gno.land", description)
	uassert.Equal(t, alice.String(), owner.String())
	uassert.Equal(t, Deposit, deposit)
	uassert.Equal(t, runtime.ChainHeight(), at)
	uassert.Equal(t, "listed", state)

	uassert.True(t, IsListed("gnoswap"))
	uassert.Equal(t, 1, Count())
	urequire.Equal(t, 1, len(Listed()))
	uassert.Equal(t, "gnoswap", Listed()[0])

	// A key that was never applied for reads as the empty state.
	_, _, _, _, _, state = Get("nothing")
	uassert.Equal(t, "", state)
	uassert.False(t, IsListed("nothing"))
}

func TestApplyRefusesAKeyAlreadyOnTheList(cur realm, t *testing.T) {
	reset()
	apply(cur, alice, "gnoswap", "https://gnoswap.io", "an AMM")

	pay(Deposit)
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "already on the list", func() {
		Apply(cross(cur), "gnoswap", "https://mine.io", "mine now")
	})

	pay(Deposit)
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "not a key", func() {
		Apply(cross(cur), "GnoSwap", "https://mine.io", "mine now")
	})
	uassert.Equal(t, 1, Count())
}

func TestChallengeMatchesTheDepositAndOpensAVote(cur realm, t *testing.T) {
	reset()
	apply(cur, alice, "gnoswap", "https://gnoswap.io", "an AMM")

	// Not a bond, not an entry: the entry is checked before the money is.
	pay(Deposit)
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "is not an entry that can be challenged", func() {
		Challenge(cross(cur), "nothing")
	})

	// An owner shielding their own entry would cost them nothing.
	pay(Deposit)
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "cannot challenge their own entry", func() {
		Challenge(cross(cur), "gnoswap")
	})

	opened := runtime.ChainHeight()
	challenge(cur, bob, "gnoswap")

	challenger, bond, deadline, keep, remove, open := ChallengeOf("gnoswap")
	urequire.True(t, open, "the challenge is readable")
	uassert.Equal(t, bob.String(), challenger.String())
	uassert.Equal(t, Deposit, bond)
	uassert.Equal(t, opened+ChallengeBlocks, deadline)
	uassert.Equal(t, int64(0), keep)
	uassert.Equal(t, int64(0), remove)
	uassert.True(t, IsListed("gnoswap"), "a challenge is an objection, not a verdict")

	// One address, one vote, and only while the window is open.
	testing.SetRealm(testing.NewUserRealm(carol))
	Vote(cross(cur), "gnoswap", false)
	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "one address, one vote", func() {
		Vote(cross(cur), "gnoswap", true)
	})

	testing.SkipHeights(ChallengeBlocks)
	testing.SetRealm(testing.NewUserRealm(dave))
	uassert.AbortsContains(t, cur, "deadline has passed", func() {
		Vote(cross(cur), "gnoswap", true)
	})
}

// The full round, with the coins checked against the chain rather than against
// the realm's own books.
func TestResolveRemovesAnEntryAndPaysTheChallenger(cur realm, t *testing.T) {
	reset()
	apply(cur, alice, "gnoswap", "https://gnoswap.io", "an AMM")
	challenge(cur, bob, "gnoswap")
	uassert.Equal(t, 2*Deposit, balance(realmAddr), "both stakes are at the realm")

	testing.SetRealm(testing.NewUserRealm(carol))
	Vote(cross(cur), "gnoswap", false)
	testing.SetRealm(testing.NewUserRealm(dave))
	Vote(cross(cur), "gnoswap", false)

	testing.SetRealm(testing.NewUserRealm(carol))
	uassert.AbortsContains(t, cur, "still open", func() { Resolve(cross(cur), "gnoswap") })

	testing.SkipHeights(ChallengeBlocks)
	// Anyone may settle it, including somebody with nothing on the outcome.
	testing.SetRealm(testing.NewUserRealm(carol))
	Resolve(cross(cur), "gnoswap")

	uassert.False(t, IsListed("gnoswap"))
	uassert.Equal(t, 0, Count())
	uassert.Equal(t, 2*Deposit, CreditOf(bob), "the bond back, plus alice's deposit")
	uassert.Equal(t, int64(0), CreditOf(alice))
	uassert.Equal(t, int64(0), CreditOf(carol), "voters are paid nothing in v0")
	uassert.Equal(t, 2*Deposit, balance(realmAddr), "credited is not sent")

	before := balance(bob)
	testing.SetRealm(testing.NewUserRealm(bob))
	got := Withdraw(cross(cur))
	uassert.Equal(t, 2*Deposit, got)
	uassert.Equal(t, before+2*Deposit, balance(bob), "the coins actually arrived")
	uassert.Equal(t, int64(0), balance(realmAddr), "and the realm kept nothing")

	// A second call, which is what a reentrant one would be, finds nothing.
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "nothing to withdraw", func() { Withdraw(cross(cur)) })
}

func TestATieKeepsTheEntryAndPaysTheOwner(cur realm, t *testing.T) {
	reset()
	apply(cur, alice, "gnoswap", "https://gnoswap.io", "an AMM")
	challenge(cur, bob, "gnoswap")

	testing.SetRealm(testing.NewUserRealm(carol))
	Vote(cross(cur), "gnoswap", true)
	testing.SetRealm(testing.NewUserRealm(dave))
	Vote(cross(cur), "gnoswap", false)

	testing.SkipHeights(ChallengeBlocks)
	testing.SetRealm(testing.NewUserRealm(bob))
	Resolve(cross(cur), "gnoswap")

	uassert.True(t, IsListed("gnoswap"), "the incumbent wins ties")
	uassert.Equal(t, Deposit, CreditOf(alice), "and takes the challenger's bond")
	uassert.Equal(t, int64(0), CreditOf(bob))

	// Her own deposit is still locked behind the entry, so only the bond is
	// collectable until she unlists.
	before := balance(alice)
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.Equal(t, Deposit, Withdraw(cross(cur)))
	uassert.Equal(t, before+Deposit, balance(alice))
	uassert.Equal(t, Deposit, balance(realmAddr), "the deposit stays behind the entry")
}

// Nobody voting is a tie too, which is the common case and the one that
// decides whether a challenge is cheap. It is not: it costs the bond.
func TestAChallengeNobodyVotedOnLoses(cur realm, t *testing.T) {
	reset()
	apply(cur, alice, "gnoswap", "https://gnoswap.io", "an AMM")
	challenge(cur, bob, "gnoswap")

	testing.SkipHeights(ChallengeBlocks)
	testing.SetRealm(testing.NewUserRealm(bob))
	Resolve(cross(cur), "gnoswap")

	uassert.True(t, IsListed("gnoswap"))
	uassert.Equal(t, Deposit, CreditOf(alice))
	uassert.Equal(t, int64(0), CreditOf(bob), "being wrong costs the bond")
}

func TestUnlistIsTheOwnersAndNotWhileChallenged(cur realm, t *testing.T) {
	reset()
	apply(cur, alice, "gnoswap", "https://gnoswap.io", "an AMM")

	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.AbortsContains(t, cur, "only the entry's owner", func() {
		Unlist(cross(cur), "gnoswap")
	})

	challenge(cur, bob, "gnoswap")
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "under challenge", func() {
		Unlist(cross(cur), "gnoswap")
	})
	uassert.Equal(t, int64(0), CreditOf(alice), "she cannot walk away mid-challenge")

	testing.SkipHeights(ChallengeBlocks)
	testing.SetRealm(testing.NewUserRealm(alice))
	Resolve(cross(cur), "gnoswap")
	testing.SetRealm(testing.NewUserRealm(alice))
	Unlist(cross(cur), "gnoswap")

	uassert.False(t, IsListed("gnoswap"))
	uassert.Equal(t, 2*Deposit, CreditOf(alice), "the bond she won, and her deposit back")

	// The key is free again, and re-listing it costs a fresh deposit.
	apply(cur, bob, "gnoswap", "https://mine.io", "mine now")
	_, _, owner, _, _, state := Get("gnoswap")
	uassert.Equal(t, bob.String(), owner.String())
	uassert.Equal(t, "listed", state)
}

// The realm holds exactly what it is accountable for, at every step: a stake
// behind something live, or a credit somebody has not collected yet.
func TestTheRealmHoldsExactlyWhatItOwes(cur realm, t *testing.T) {
	reset()
	check := func(step string) {
		t.Helper()
		uassert.Equal(t, list.Locked()+list.Owed(), balance(realmAddr), step)
	}
	check("empty")

	apply(cur, alice, "one", "https://1.io", "first")
	check("after a listing")

	apply(cur, bob, "two", "https://2.io", "second")
	check("after a second listing")

	challenge(cur, bob, "one")
	check("after a challenge")

	testing.SetRealm(testing.NewUserRealm(carol))
	Vote(cross(cur), "one", false)
	check("after a vote")

	testing.SkipHeights(ChallengeBlocks)
	testing.SetRealm(testing.NewUserRealm(carol))
	Resolve(cross(cur), "one")
	check("after a resolution")

	testing.SetRealm(testing.NewUserRealm(bob))
	Withdraw(cross(cur))
	check("after the winner collected")

	testing.SetRealm(testing.NewUserRealm(bob))
	Unlist(cross(cur), "two")
	check("after an unlisting")

	testing.SetRealm(testing.NewUserRealm(bob))
	Withdraw(cross(cur))
	check("after the deposit came back")
	uassert.Equal(t, int64(0), balance(realmAddr), "and the realm is empty again")
}

// A URL is caller-supplied too, and it is the one string that reaches the
// renderer as a link target rather than as text.
func TestAPipeInAUrlCannotOpenAColumn(cur realm, t *testing.T) {
	reset()
	apply(cur, alice, "weird", "https://x.io/a|b", "a url with a pipe in it")

	index := Render("")
	uassert.False(t, strings.Contains(index, "https://x.io/a|b"),
		"the raw pipe would open a column: "+index)
	uassert.True(t, strings.Contains(index, "https://x.io/a%7Cb"),
		"the link sanitizer percent-encodes it: "+index)
}

// TestRender uses uassert rather than an Example because every view contains
// consecutive blank lines, which gno collapses inside an // Output: block.
func TestRender(cur realm, t *testing.T) {
	reset()
	apply(cur, alice, "gnoswap", "https://gnoswap.io/pools?a=1", "an AMM | with [a link](x)")

	index := Render("")
	uassert.True(t, strings.Contains(index, "# Curated"), index)
	uassert.True(t, strings.Contains(index, "| 1 | 0 |"), "one listed, none challenged: "+index)
	uassert.True(t, strings.Contains(index, "func=Apply"), "the index offers the transaction")
	uassert.True(t, strings.Contains(index, "Voters are paid nothing"), "the index says what v0 does not do")
	uassert.True(t, strings.Contains(index, "an AMM \\| with \\[a link\\]\\(x\\)"),
		"a pipe in a description cannot open a column, and its markdown is inert: "+index)

	entry := Render("entry/gnoswap")
	uassert.True(t, strings.Contains(entry, "# gnoswap"), entry)
	uassert.True(t, strings.Contains(entry, "an AMM | with \\[a link\\]\\(x\\)"),
		"the description is escaped in prose too, where a pipe is not special: "+entry)
	uassert.True(t, strings.Contains(entry, "func=Challenge"))
	uassert.True(t, strings.Contains(entry, "func=Unlist"))

	// Under challenge the page offers the two votes instead.
	challenge(cur, bob, "gnoswap")
	entry = Render("entry/gnoswap")
	uassert.True(t, strings.Contains(entry, "## Under challenge"), entry)
	uassert.True(t, strings.Contains(entry, "keep=true"), entry)
	uassert.True(t, strings.Contains(entry, "keep=false"), entry)
	uassert.False(t, strings.Contains(entry, "func=Unlist"), "an owner cannot walk away here either")
	uassert.True(t, strings.Contains(Render(""), "## Open challenges"))

	testing.SetRealm(testing.NewUserRealm(carol))
	Vote(cross(cur), "gnoswap", false)
	testing.SetRealm(testing.NewUserRealm(dave))
	Vote(cross(cur), "gnoswap", false)

	// Past the deadline it offers the settlement instead of the votes.
	testing.SkipHeights(ChallengeBlocks)
	entry = Render("entry/gnoswap")
	uassert.True(t, strings.Contains(entry, "func=Resolve"), entry)
	uassert.False(t, strings.Contains(entry, "keep=true"), "voting is over: "+entry)

	// Removed, the key is advertised as free again.
	testing.SetRealm(testing.NewUserRealm(bob))
	Resolve(cross(cur), "gnoswap")

	entry = Render("entry/gnoswap")
	uassert.True(t, strings.Contains(entry, "free to apply for again"), entry)
	uassert.True(t, strings.Contains(Render(""), "Nothing is on the list yet."))

	uassert.Equal(t, "# Curated\nNo entry named nope", Render("entry/nope"))
	uassert.True(t, strings.HasPrefix(Render("elsewhere"), "# Not found"))
}
