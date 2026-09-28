package nativeify

import (
	"chain"
	"chain/banker"
	"strings"
	"testing"

	"gno.land/p/moul/x/envelope/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/r/moul/x/grc20faucet/v0"
	"gno.land/r/moul/x/nativereg/v0"
)

// Two things about the harness shape every test below.
//
// testing.SetRealm governs only the crossing calls made from the frame that
// called it, so every account switch is inline in the test body.
//
// The BANK does not carry over between test functions while realm state does,
// so native balances, TotalCoin and the escrowed GRC20 cannot be compared
// across tests. Everything here is asserted as a delta inside one test.

func TestNativeifyCreatesThePair(cur realm, t *testing.T) {
	alice := testutils.TestAddress("nf-alice")
	testing.SetRealm(testing.NewUserRealm(alice))

	denom := Nativeify(cross(cur), grc20faucet.RedKey, "nred")
	uassert.Equal(t, "/gno.land/r/moul/x/nativeify/v0:nred", denom)
	uassert.Equal(t, denom, Denom("nred"))
	uassert.Equal(t, grc20faucet.RedKey, TokenKey("nred"))

	// The denom names this realm, so this realm is the only thing on the chain
	// that can describe it, and it did.
	e := nativereg.MustGet(denom)
	uassert.Equal(t, Path, e.Issuer)
	uassert.Equal(t, "nRED", e.Symbol)
	uassert.Equal(t, 4, e.Decimals, "the underlying's decimals travel as a display hint")

	uassert.AbortsContains(t, cur, "already issues nred", func() {
		Nativeify(cross(cur), grc20faucet.BlueKey, "nred")
	})
	uassert.AbortsContains(t, cur, "already native here", func() {
		Nativeify(cross(cur), grc20faucet.RedKey, "nred2")
	})
	uassert.AbortsContains(t, cur, "unknown token", func() {
		Nativeify(cross(cur), "gno.land/r/nope/nope.NOPE", "nnope")
	})
}

func TestBaseNameFollowsTheChainsRule(cur realm, t *testing.T) {
	bob := testutils.TestAddress("nf-bob")
	testing.SetRealm(testing.NewUserRealm(bob))

	// The chain's own rule, applied here so the caller reads a sentence instead
	// of a banker stack trace: a lowercase letter, then 2 to 15 more lowercase
	// letters or digits.
	uassert.AbortsContains(t, cur, "is 2 characters", func() {
		Nativeify(cross(cur), grc20faucet.BlueKey, "ab")
	})
	uassert.AbortsContains(t, cur, "is 17 characters", func() {
		Nativeify(cross(cur), grc20faucet.BlueKey, strings.Repeat("a", 17))
	})
	uassert.AbortsContains(t, cur, "is not", func() {
		Nativeify(cross(cur), grc20faucet.BlueKey, "nBLUE")
	})
	uassert.AbortsContains(t, cur, "is not", func() {
		Nativeify(cross(cur), grc20faucet.BlueKey, "1blue")
	})
	uassert.AbortsContains(t, cur, "is not", func() {
		Nativeify(cross(cur), grc20faucet.BlueKey, "n-blue")
	})

	// And one that is legal all the way through.
	uassert.Equal(t, "/gno.land/r/moul/x/nativeify/v0:nblue1",
		Nativeify(cross(cur), grc20faucet.BlueKey, "nblue1"))
}

func TestWrapNeedsAnAllowanceFirst(cur realm, t *testing.T) {
	carol := testutils.TestAddress("nf-carol")
	testing.SetRealm(testing.NewUserRealm(carol))
	grc20faucet.Claim(cross(cur))

	// Until the holder names this realm on the underlying token, this realm has
	// no authority over their balance whatsoever. That is the GRC20 half of the
	// trade, and it is the half a native coin does not have.
	uassert.AbortsContains(t, cur, "allowance", func() { Wrap(cross(cur), "nred", 1_000) })
	uassert.Equal(t, int64(0), envelope.BalanceOf(carol, Denom("nred")))
}

func TestWrapEscrowsAndIssues(cur realm, t *testing.T) {
	dave := testutils.TestAddress("nf-dave")
	testing.SetRealm(testing.NewUserRealm(dave))
	grc20faucet.Claim(cross(cur))
	grc20faucet.Approve(cross(cur), "RED", Home(), 1_000_000)

	denom := Denom("nred")
	redBefore := grc20faucet.BalanceOf("RED", dave)
	escrowBefore, issuedBefore := Solvency("nred")

	got := Wrap(cross(cur), "nred", 400_000)

	uassert.Equal(t, int64(400_000), got)
	uassert.Equal(t, redBefore-400_000, grc20faucet.BalanceOf("RED", dave), "the GRC20 left the holder")
	uassert.Equal(t, escrowBefore+400_000, grc20faucet.BalanceOf("RED", Home()), "and landed in escrow")
	uassert.Equal(t, int64(400_000), envelope.BalanceOf(dave, denom), "the native coin is at the bank, 1:1")

	escrowAfter, issuedAfter := Solvency("nred")
	uassert.Equal(t, escrowBefore+400_000, escrowAfter)
	uassert.Equal(t, issuedBefore+400_000, issuedAfter)
	uassert.True(t, IsSolvent("nred"), "every coin issued is backed")

	uassert.AbortsContains(t, cur, "positive amount", func() { Wrap(cross(cur), "nred", 0) })
	uassert.AbortsContains(t, cur, "does not issue", func() { Wrap(cross(cur), "ghost", 1) })
}

func TestUnwrapDestroysTheCoinAndReleasesTheBacking(cur realm, t *testing.T) {
	erin := testutils.TestAddress("nf-erin")
	denom := Denom("nred")

	testing.SetRealm(testing.NewUserRealm(erin))
	grc20faucet.Claim(cross(cur))
	grc20faucet.Approve(cross(cur), "RED", Home(), 1_000_000)
	Wrap(cross(cur), "nred", 300_000)

	// On chain the -send envelope moves the coins to this realm's address before
	// Unwrap runs. The harness has no bank-send primitive, so the credit is
	// issued here; SetOriginSend is the half the realm actually reads.
	sent := chain.NewCoins(chain.NewCoin(denom, 120_000))
	testing.IssueCoins(Home(), sent)
	testing.SetOriginSend(sent)

	redBefore := grc20faucet.BalanceOf("RED", erin)
	escrowBefore := grc20faucet.BalanceOf("RED", Home())
	_, issuedBefore := Solvency("nred")

	got := Unwrap(cross(cur), "nred")

	uassert.Equal(t, int64(120_000), got)
	uassert.Equal(t, redBefore+120_000, grc20faucet.BalanceOf("RED", erin), "the backing came back")
	uassert.Equal(t, escrowBefore-120_000, grc20faucet.BalanceOf("RED", Home()), "escrow shrank by the same")
	_, issuedAfter := Solvency("nred")
	uassert.Equal(t, issuedBefore-120_000, issuedAfter,
		"the coins were destroyed, not moved: total supply fell")

	testing.SetOriginSend(nil)
	uassert.AbortsContains(t, cur, "must be paid", func() { Unwrap(cross(cur), "nred") })
}

func TestRender(cur realm, t *testing.T) {
	index := Render("")
	uassert.True(t, strings.Contains(index, "# nativeify"), index)
	uassert.True(t, strings.Contains(index, Home().String()), "the escrow address is on the page")
	uassert.True(t, strings.Contains(index, "| [nred](/r/moul/x/nativeify/v0:nred) |"),
		"the pair is listed:\n"+index)

	one := Render("nred")
	uassert.True(t, strings.Contains(one, "/gno.land/r/moul/x/nativeify/v0:nred"), one)
	uassert.True(t, strings.Contains(one, "a display hint only"), one)

	uassert.True(t, strings.Contains(Render("ghost"), "404"), "an unknown base renders a 404")
}

// attemptPull is the thing a GRC20 facade over a native coin would have to do,
// written out so it can be shown failing. It is in the test file, so it is not
// part of the deployed package.
func attemptPull(cur realm, from address, denom string, amount int64) {
	banker.NewBanker(banker.BankerTypeRealmIssue, cur).
		SendCoins(from, Home(), chain.NewCoins(chain.NewCoin(denom, amount)))
}

func TestARealmCannotPullANativeCoin(cur realm, t *testing.T) {
	// The claim the package doc rests on, pinned rather than asserted: this
	// realm holds the strongest banker the chain offers, the one that can mint
	// and destroy this denom at will, and it still cannot MOVE a unit it does
	// not already hold. There is no allowance to grant and no TransferFrom to
	// call, which is why a grc20.Teller over a native coin cannot be written and
	// why wugnot wraps in the direction it does.
	frank := testutils.TestAddress("nf-frank")
	denom := Denom("nred")
	testing.IssueCoins(frank, chain.NewCoins(chain.NewCoin(denom, 1_000)))

	msg := pullError(cur, frank, denom, 1_000)
	uassert.True(t, strings.Contains(msg, "can only send coins from realm that created banker"),
		"got: "+msg)
	uassert.Equal(t, int64(1_000), envelope.BalanceOf(frank, denom), "and nothing moved")
}

// pullError runs attemptPull and returns the refusal as a string.
//
// uassert.PanicsContains cannot read this one. banker.SendCoins builds its
// message as `"..." + b.pkgAddr + "..."`, and in gno a string concatenated with
// an `address` has type `address`, so the panic value is an address rather than
// a string and the helper reports "recover: unsupported type". Measured
// 2026-09-28 against gno master; the message itself is correct, only its type is
// surprising.
func pullError(cur realm, from address, denom string, amount int64) (msg string) {
	defer func() {
		switch r := recover().(type) {
		case nil:
			msg = "it did not fail at all"
		case address:
			msg = string(r)
		case string:
			msg = r
		case error:
			msg = r.Error()
		default:
			msg = "panicked with an unexpected type"
		}
	}()
	attemptPull(cur, from, denom, amount)
	return ""
}

// ---------------------------------------------------------------------------
// p/moul/x/envelope's Forward is exercised here rather than in its own package:
// minting a BankerTypeOriginSend banker calls rlm.Previous(), and a p/ package's
// test has no realm frame to walk, so it dies with "frame not found: cannot seek
// beyond origin caller override". A p/ helper that needs a realm handle can only
// be tested from a realm.

func forwardDirect(cur realm, to address, coins chain.Coins) {
	envelope.Forward(0, cur, to, coins)
}

func forwardOneDeeper(cur realm, to address, coins chain.Coins) {
	forwardDirect(cur, to, coins)
}

func TestForwardIsBoundedByTheEnvelope(cur realm, t *testing.T) {
	to := testutils.TestAddress("nf-forward-to")
	denom := Denom("nred")

	// The realm holds 5,000 of its own, and the envelope carried 250. A
	// RealmSend banker could spend all 5,250; this one may spend 250.
	testing.IssueCoins(Home(), chain.NewCoins(chain.NewCoin(denom, 5_000)))
	sent := chain.NewCoins(chain.NewCoin(denom, 250))
	testing.IssueCoins(Home(), sent)
	testing.SetOriginSend(sent)

	heldBefore := envelope.BalanceOf(Home(), denom)
	forwardDirect(cur, to, sent)

	uassert.Equal(t, int64(250), envelope.BalanceOf(to, denom))
	uassert.Equal(t, heldBefore-250, envelope.BalanceOf(Home(), denom),
		"exactly the envelope left, and none of the realm's own balance")

	// Spending past the envelope is refused by the VM, not by any check here.
	uassert.PanicsContains(t, cur, "limit", func() {
		forwardDirect(cur, to, chain.NewCoins(chain.NewCoin(denom, 5_000)))
	})
	testing.SetOriginSend(nil)
}

func TestForwardFromOneFrameDeeper(cur realm, t *testing.T) {
	// The frame-depth rule, measured rather than assumed: NewBanker refuses
	// BankerTypeOriginSend unless rlm.Previous().IsUserCall(), and IsUserCall
	// counts at most two call-boundary frames. Whatever this run reports is what
	// the package doc says.
	to := testutils.TestAddress("nf-deep-to")
	denom := Denom("nred")
	sent := chain.NewCoins(chain.NewCoin(denom, 90))
	testing.IssueCoins(Home(), sent)
	testing.SetOriginSend(sent)

	forwardOneDeeper(cur, to, sent)
	uassert.Equal(t, int64(90), envelope.BalanceOf(to, denom),
		"one extra frame between the entry point and Forward")
	testing.SetOriginSend(nil)
}
