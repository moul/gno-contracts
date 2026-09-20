package grc20wrapdemo

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	faucet "gno.land/r/moul/x/grc20faucet/v0"
)

// Realm state carries over between test functions, but the block height does
// not: every test starts from the same height. The faucet's per-account
// cooldown would therefore fire on the second test to reuse an account, so each
// test claims with its own. TestFaucetCooldown covers the cooldown itself.
func fund(cur realm, t *testing.T, name string) address {
	t.Helper()
	who := testutils.TestAddress(name)
	testing.SetRealm(testing.NewUserRealm(who))
	faucet.Claim(cross(cur))
	faucet.Approve(cross(cur), "RED", Home(), faucet.ClaimAmount)
	faucet.Approve(cross(cur), "BLUE", Home(), faucet.ClaimAmount)
	return who
}

// testing.SetRealm only governs crossing calls made from the frame that called
// it: put it in a helper with no crossing call of its own and it is silently
// ignored, and the caller stays whoever it was. fund() gets away with it
// because it crosses into the faucet right after; switching accounts mid-test
// has to be written inline, which is why there is no act() helper here.

// The plain mode is the baseline: it proves custody actually crosses a realm
// boundary. The RED never belonged to this realm, and it can only ever take
// what the faucet's Approve handed over.
func TestPlainWrapperRoundTrip(cur realm, t *testing.T) {
	alice := fund(cur, t, "w-alice")
	before := faucet.BalanceOf("RED", alice)

	key := NewWrapper(cross(cur), faucet.RedKey, "plain", "wRED")
	uassert.True(t, strings.HasSuffix(key, ".wRED"), "registered under its own symbol: "+key)

	minted := Deposit(cross(cur), "wRED", 400_000)
	uassert.Equal(t, int64(400_000), minted)
	uassert.Equal(t, int64(400_000), BalanceOf("wRED", alice))
	uassert.Equal(t, int64(400_000), Escrow("wRED"))
	uassert.Equal(t, before-400_000, faucet.BalanceOf("RED", alice))
	// The escrow really sits at this realm's address, in the faucet's ledger.
	uassert.Equal(t, int64(400_000), faucet.BalanceOf("RED", Home()))

	back := Withdraw(cross(cur), "wRED", 150_000)
	uassert.Equal(t, int64(150_000), back)
	uassert.Equal(t, int64(250_000), TotalSupply("wRED"))
	uassert.Equal(t, before-250_000, faucet.BalanceOf("RED", alice))
}

// Depositing without an allowance is the default state of the world, and it
// fails. This realm holds no standing authority over anybody's balance.
func TestDepositNeedsAnAllowance(cur realm, t *testing.T) {
	fund(cur, t, "noallow")
	NewWrapper(cross(cur), faucet.RedKey, "plain", "noallow")

	// Revoke what fund() granted.
	faucet.Approve(cross(cur), "RED", Home(), 0)
	uassert.AbortsContains(t, cur, "insufficient allowance", func() {
		Deposit(cross(cur), "noallow", 1)
	})
	uassert.Equal(t, int64(0), TotalSupply("noallow"))
}

// kilo re-denominates a token whose own realm will never redeploy for it.
func TestKiloWrapperAddsThreeDecimals(cur realm, t *testing.T) {
	fund(cur, t, "kilo")
	NewWrapper(cross(cur), faucet.RedKey, "kilo", "kRED")

	minted := Deposit(cross(cur), "kRED", 1_000)
	uassert.Equal(t, int64(1_000_000), minted)
	uassert.Equal(t, int64(1_000), Escrow("kRED"))

	back := Withdraw(cross(cur), "kRED", 999_000)
	uassert.Equal(t, int64(999), back)
	// 999 wrapped units cannot buy back a whole underlying one, so the
	// redemption is refused rather than burning them for nothing.
	uassert.AbortsContains(t, cur, "rounds to zero", func() {
		Withdraw(cross(cur), "kRED", 999)
	})
}

func TestSoulboundWrapperRefusesTransfer(cur realm, t *testing.T) {
	fund(cur, t, "soul")
	bob := testutils.TestAddress("soul-bob")
	NewWrapper(cross(cur), faucet.RedKey, "soulbound", "sRED")
	Deposit(cross(cur), "sRED", 300_000)

	uassert.AbortsContains(t, cur, "soulbound", func() {
		Transfer(cross(cur), "sRED", bob, 1)
	})
	uassert.Equal(t, int64(0), BalanceOf("sRED", bob))

	// The exit stays open: unwrap, and the RED moves as freely as ever.
	back := Withdraw(cross(cur), "sRED", 300_000)
	uassert.Equal(t, int64(300_000), back)
	uassert.Equal(t, int64(0), TotalSupply("sRED"))
}

// Pool: a donation is shared by whoever is holding, and the donor can never
// take it back out.
func TestPoolWrapperSharesDonations(cur realm, t *testing.T) {
	alice := fund(cur, t, "pool-a")
	NewWrapper(cross(cur), faucet.RedKey, "pool", "pRED")
	uassert.Equal(t, int64(100_000), Deposit(cross(cur), "pRED", 100_000))

	bob := fund(cur, t, "pool-b")
	Donate(cross(cur), "pRED", 100_000)
	uassert.Equal(t, int64(200_000), Escrow("pRED"))
	uassert.Equal(t, int64(100_000), TotalSupply("pRED"))
	uassert.Equal(t, int64(0), BalanceOf("pRED", bob)) // a donation mints nothing

	// Buying in afterwards costs twice as much per share.
	uassert.Equal(t, int64(50_000), Deposit(cross(cur), "pRED", 100_000))

	// alice walks away with double what she put in.
	testing.SetRealm(testing.NewUserRealm(alice))
	redBefore := faucet.BalanceOf("RED", alice)
	uassert.Equal(t, int64(200_000), Withdraw(cross(cur), "pRED", 100_000))
	uassert.Equal(t, redBefore+200_000, faucet.BalanceOf("RED", alice))

	// And bob gets back exactly the 100_000 he deposited: his own donation
	// was to the holders, and by then that was alice.
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.Equal(t, int64(100_000), Withdraw(cross(cur), "pRED", 50_000))
	uassert.Equal(t, int64(0), Escrow("pRED"))
}

// Sticky: the 1% exit fee is collected by nobody, it is left in the pool, so
// whoever stays longest ends up with it.
func TestStickyWrapperChargesOnTheWayOut(cur realm, t *testing.T) {
	alice := fund(cur, t, "stick-a")
	NewWrapper(cross(cur), faucet.RedKey, "sticky", "fRED")
	Deposit(cross(cur), "fRED", 500_000)

	bob := fund(cur, t, "stick-b")
	Deposit(cross(cur), "fRED", 500_000)
	uassert.Equal(t, int64(1_000_000), TotalSupply("fRED"))

	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.Equal(t, int64(495_000), Withdraw(cross(cur), "fRED", 500_000))

	// The 5_000 alice paid on the way out now backs bob's shares.
	uassert.Equal(t, int64(505_000), Escrow("fRED"))
	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.Equal(t, int64(499_950), Withdraw(cross(cur), "fRED", 500_000))
}

// Fusion: one token backed by a fixed bundle of two, and nothing else.
func TestFusionOfRedAndBlue(cur realm, t *testing.T) {
	alice := fund(cur, t, "fuse-a")
	bob := testutils.TestAddress("fuse-b")

	key := NewFusion(cross(cur), faucet.RedKey, 1, faucet.BlueKey, 2, "PURPLE")
	uassert.True(t, strings.HasSuffix(key, ".PURPLE"), key)
	uassert.Equal(t, 2, Legs("PURPLE"))

	redBefore := faucet.BalanceOf("RED", alice)
	blueBefore := faucet.BalanceOf("BLUE", alice)
	Fuse(cross(cur), "PURPLE", 100_000)

	uassert.Equal(t, int64(100_000), BalanceOf("PURPLE", alice))
	uassert.Equal(t, redBefore-100_000, faucet.BalanceOf("RED", alice))
	uassert.Equal(t, blueBefore-200_000, faucet.BalanceOf("BLUE", alice))

	sym, per, held := Leg("PURPLE", 1)
	uassert.Equal(t, "BLUE", sym)
	uassert.Equal(t, int64(2), per)
	uassert.Equal(t, int64(200_000), held)

	// PURPLE moves as one object, and whoever ends up with it can split it
	// back into both legs without ever having touched the faucet.
	Transfer(cross(cur), "PURPLE", bob, 40_000)
	testing.SetRealm(testing.NewUserRealm(bob))
	Defuse(cross(cur), "PURPLE", 40_000)
	uassert.Equal(t, int64(40_000), faucet.BalanceOf("RED", bob))
	uassert.Equal(t, int64(80_000), faucet.BalanceOf("BLUE", bob))
	uassert.Equal(t, int64(60_000), TotalSupply("PURPLE"))
}

// Every token issued here is registered too, so it can be wrapped again.
func TestWrappingAWrapper(cur realm, t *testing.T) {
	fund(cur, t, "nest")
	NewWrapper(cross(cur), faucet.RedKey, "plain", "nRED")
	Deposit(cross(cur), "nRED", 800_000)

	// nRED lives in THIS realm, so the allowance is granted through this
	// realm's own Approve. Same shape, one level up.
	NewWrapper(cross(cur), Key("nRED"), "pool", "nnRED")
	Approve(cross(cur), "nRED", Home(), 800_000)
	uassert.Equal(t, int64(600_000), Deposit(cross(cur), "nnRED", 600_000))

	// The outer wrapper escrows the inner token, not the RED.
	uassert.Equal(t, int64(600_000), Escrow("nnRED"))
	uassert.Equal(t, int64(800_000), Escrow("nRED"))
	uassert.Equal(t, int64(600_000), BalanceOf("nRED", Home()))

	// And it unwinds the whole way back down.
	uassert.Equal(t, int64(600_000), Withdraw(cross(cur), "nnRED", 600_000))
	uassert.Equal(t, int64(800_000), Withdraw(cross(cur), "nRED", 800_000))
	uassert.Equal(t, int64(0), TotalSupply("nRED"))
}

func TestAllowanceOnAWrappedToken(cur realm, t *testing.T) {
	alice := fund(cur, t, "allow-a")
	bob := testutils.TestAddress("allow-b")

	NewWrapper(cross(cur), faucet.RedKey, "plain", "aRED")
	Deposit(cross(cur), "aRED", 500_000)
	Approve(cross(cur), "aRED", bob, 120_000)
	uassert.Equal(t, int64(120_000), Allowance("aRED", alice, bob))

	testing.SetRealm(testing.NewUserRealm(bob))
	TransferFrom(cross(cur), "aRED", alice, bob, 120_000)
	uassert.Equal(t, int64(120_000), BalanceOf("aRED", bob))
	uassert.AbortsContains(t, cur, "insufficient allowance", func() {
		TransferFrom(cross(cur), "aRED", alice, bob, 1)
	})
}

func TestFaucetCooldown(cur realm, t *testing.T) {
	who := fund(cur, t, "cooldown")
	uassert.AbortsContains(t, cur, "too soon", func() {
		faucet.Claim(cross(cur))
	})

	next, ok := faucet.NextClaim(who)
	uassert.True(t, ok, "the account has claimed once")
	testing.SkipHeights(faucet.ClaimEvery + 1)
	faucet.Claim(cross(cur))
	uassert.Equal(t, 2*faucet.ClaimAmount, faucet.BalanceOf("RED", who))
	uassert.True(t, next > 0, "a cooldown was recorded")

	_, ok = faucet.NextClaim(testutils.TestAddress("never"))
	uassert.False(t, ok, "an account that never claimed has no cooldown")
}

func TestRejectsBadInput(cur realm, t *testing.T) {
	fund(cur, t, "bad")
	NewWrapper(cross(cur), faucet.RedKey, "plain", "xRED")
	NewFusion(cross(cur), faucet.RedKey, 1, faucet.BlueKey, 1, "xMIX")

	uassert.AbortsContains(t, cur, "unknown mode", func() {
		NewWrapper(cross(cur), faucet.RedKey, "moon", "xMOON")
	})
	uassert.AbortsContains(t, cur, "already issued by this realm", func() {
		NewWrapper(cross(cur), faucet.RedKey, "plain", "xRED")
	})
	uassert.AbortsContains(t, cur, "unknown token", func() {
		NewWrapper(cross(cur), "gno.land/r/nope/nope.NOPE", "plain", "xNOPE")
	})
	uassert.AbortsContains(t, cur, "is a fusion", func() {
		Deposit(cross(cur), "xMIX", 1)
	})
	uassert.AbortsContains(t, cur, "is a wrapper", func() {
		Fuse(cross(cur), "xRED", 1)
	})
	uassert.AbortsContains(t, cur, "has not issued", func() {
		Deposit(cross(cur), "GHOST", 1)
	})
	uassert.AbortsContains(t, cur, "unknown symbol", func() {
		faucet.Transfer(cross(cur), "GREEN", Home(), 1)
	})
}

func TestRender(cur realm, t *testing.T) {
	fund(cur, t, "render")
	NewWrapper(cross(cur), faucet.RedKey, "pool", "rRED")
	Deposit(cross(cur), "rRED", 250_000)

	index := Render("")
	uassert.True(t, strings.Contains(index, "# GRC20 wrapper factory"), "index heading")
	uassert.True(t, strings.Contains(index, Home().String()), "index shows the escrow address")
	uassert.True(t, strings.Contains(index, "| [rRED](/r/moul/x/grc20wrapdemo/v0:rRED) | pool | RED |"),
		"index lists the wrapper:\n"+index)

	detail := Render("rRED")
	uassert.True(t, strings.Contains(detail, "escrowed underlying: 250000"), detail)
	uassert.True(t, strings.Contains(detail, "- mode: `pool`"), detail)
	uassert.True(t, strings.Contains(detail, "solvent: yes"), detail)

	uassert.True(t, strings.Contains(Render("NOPE"), "404"), "unknown symbol renders a 404")
}
