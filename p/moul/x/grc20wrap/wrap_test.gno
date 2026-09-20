package grc20wrap

import (
	"testing"

	"gno.land/p/nt/grc20/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

// The two realms every test needs: one that issues the underlying token, one
// that wraps it. They MUST be distinct, because wrapping a token issued by your
// own realm exercises none of the interesting machinery: the allowance, the
// eagerly-bound teller, the foreign escrow.
const (
	underPath = "gno.land/r/test/under"
	wrapPath  = "gno.land/r/test/wrapper"
)

var (
	alice = testutils.TestAddress("alice")
	bob   = testutils.TestAddress("bob")
	carl  = testutils.TestAddress("carl")
)

// mintUnder issues the underlying token from underPath and funds holders.
func mintUnder(cur realm, t *testing.T, funded ...address) (*grc20.Token, *grc20.PrivateLedger) {
	t.Helper()
	testing.SetRealm(testing.NewCodeRealm(underPath))
	tok, led := grc20.NewToken("Under", "UND", 4, 0, cur)
	for _, a := range funded {
		urequire.NoError(t, led.Mint(a, 1_000))
	}
	return tok, led
}

// approve stands in for the underlying realm's own Approve entry point: on
// chain the holder calls it, here the ledger does it on their behalf.
func approve(cur realm, t *testing.T, led *grc20.PrivateLedger, owner, spender address, amount int64) {
	t.Helper()
	urequire.NoError(t, led.ImpersonateTeller(owner).Approve(0, cur, spender, amount))
}

func TestOneToOneRoundTrip(cur realm, t *testing.T) {
	under, led := mintUnder(cur, t, alice)

	testing.SetRealm(testing.NewCodeRealm(wrapPath))
	v := NewVault(under, OneToOne{}, "Wrapped Under", "wUND", 4, 0, cur)
	approve(cur, t, led, alice, v.Home(), 1_000)

	out, err := v.Wrap(0, cur, alice, 400)
	urequire.NoError(t, err)
	uassert.Equal(t, int64(400), out)
	uassert.Equal(t, int64(400), v.Token().BalanceOf(alice))
	uassert.Equal(t, int64(600), under.BalanceOf(alice))
	uassert.Equal(t, int64(400), v.Held())
	uassert.Equal(t, int64(400), v.Custody())
	uassert.True(t, v.Solvent())

	back, err := v.Unwrap(0, cur, alice, 150)
	urequire.NoError(t, err)
	uassert.Equal(t, int64(150), back)
	uassert.Equal(t, int64(250), v.Token().BalanceOf(alice))
	uassert.Equal(t, int64(250), v.Supply())
	uassert.Equal(t, int64(750), under.BalanceOf(alice))
	uassert.Equal(t, int64(250), v.Held())
	uassert.True(t, v.Solvent())
}

// Escrow is pulled with an allowance, so a wrapper can never take more than a
// holder granted it. This is the property that makes a wrapper safe to publish
// as a permissionless factory: it has no authority nobody handed it.
func TestWrapStopsAtTheAllowance(cur realm, t *testing.T) {
	under, led := mintUnder(cur, t, alice)

	testing.SetRealm(testing.NewCodeRealm(wrapPath))
	v := NewVault(under, OneToOne{}, "Wrapped Under", "wUND", 4, 0, cur)
	approve(cur, t, led, alice, v.Home(), 100)

	_, err := v.Wrap(0, cur, alice, 101)
	uassert.ErrorContains(t, err, "insufficient allowance")
	uassert.Equal(t, int64(0), v.Supply())
	uassert.Equal(t, int64(1_000), under.BalanceOf(alice))

	_, err = v.Wrap(0, cur, alice, 0)
	uassert.ErrorIs(t, err, ErrInvalidAmount)
}

// Unwrapping is bounded by the wrapped balance, not by the escrow: a holder
// cannot redeem somebody else's deposit.
func TestUnwrapStopsAtTheBalance(cur realm, t *testing.T) {
	under, led := mintUnder(cur, t, alice, bob)

	testing.SetRealm(testing.NewCodeRealm(wrapPath))
	v := NewVault(under, OneToOne{}, "Wrapped Under", "wUND", 4, 0, cur)
	approve(cur, t, led, alice, v.Home(), 1_000)
	approve(cur, t, led, bob, v.Home(), 1_000)

	_, err := v.Wrap(0, cur, alice, 500)
	urequire.NoError(t, err)
	_, err = v.Wrap(0, cur, bob, 500)
	urequire.NoError(t, err)
	uassert.Equal(t, int64(1_000), v.Held())

	_, err = v.Unwrap(0, cur, bob, 501)
	uassert.ErrorContains(t, err, "insufficient balance")
	uassert.Equal(t, int64(1_000), v.Held())
}

// Ratio gives a token more decimals than the realm that issued it ever offered.
func TestRatioRedenominates(cur realm, t *testing.T) {
	under, led := mintUnder(cur, t, alice)

	testing.SetRealm(testing.NewCodeRealm(wrapPath))
	v := NewVault(under, Ratio{Num: 1_000, Den: 1}, "Kilo Under", "kUND", 7, 0, cur)
	approve(cur, t, led, alice, v.Home(), 1_000)

	out, err := v.Wrap(0, cur, alice, 5)
	urequire.NoError(t, err)
	uassert.Equal(t, int64(5_000), out)
	uassert.Equal(t, int64(5), v.Held())

	back, err := v.Unwrap(0, cur, alice, 3_000)
	urequire.NoError(t, err)
	uassert.Equal(t, int64(3), back)
	uassert.Equal(t, int64(2), v.Held())

	// A redemption too small to buy one underlying unit is refused rather
	// than silently burning the wrapped units for nothing.
	_, err = v.Unwrap(0, cur, alice, 999)
	uassert.ErrorIs(t, err, ErrDust)
	uassert.Equal(t, int64(2_000), v.Supply())
}

// Soulbound: wrap in, unwrap out, but never hand the receipt to anybody.
func TestSoulboundReceipt(cur realm, t *testing.T) {
	under, led := mintUnder(cur, t, alice)

	testing.SetRealm(testing.NewCodeRealm(wrapPath))
	v := NewVault(under, Soulbound{}, "Bound Under", "sUND", 4, 0, cur)
	approve(cur, t, led, alice, v.Home(), 1_000)

	_, err := v.Wrap(0, cur, alice, 300)
	urequire.NoError(t, err)

	uassert.ErrorIs(t, v.Move(alice, bob, 1), ErrSoulbound)
	uassert.Equal(t, int64(0), v.Token().BalanceOf(bob))

	// An allowance may be granted, and is still worthless when spent.
	urequire.NoError(t, v.Allow(alice, bob, 100))
	uassert.ErrorIs(t, v.MoveFrom(bob, alice, carl, 100), ErrSoulbound)

	// The exit is always open: unwrap, then move the underlying.
	back, err := v.Unwrap(0, cur, alice, 300)
	urequire.NoError(t, err)
	uassert.Equal(t, int64(300), back)
	uassert.Equal(t, int64(0), v.Supply())
}

// Pool is the yield-bearing pattern: a donation nobody can withdraw raises what
// every share redeems for, and later depositors buy in at the new price.
func TestPoolSharesAppreciate(cur realm, t *testing.T) {
	under, led := mintUnder(cur, t, alice, bob, carl)

	testing.SetRealm(testing.NewCodeRealm(wrapPath))
	v := NewVault(under, Pool{}, "Pooled Under", "pUND", 4, 0, cur)
	for _, a := range []address{alice, bob, carl} {
		approve(cur, t, led, a, v.Home(), 1_000)
	}

	// First in, priced 1:1 because the pool is empty.
	out, err := v.Wrap(0, cur, alice, 100)
	urequire.NoError(t, err)
	uassert.Equal(t, int64(100), out)

	// bob donates: escrow doubles, share count does not move.
	urequire.NoError(t, v.Donate(0, cur, bob, 100))
	uassert.Equal(t, int64(200), v.Held())
	uassert.Equal(t, int64(100), v.Supply())

	// carl now pays twice as much per share.
	out, err = v.Wrap(0, cur, carl, 100)
	urequire.NoError(t, err)
	uassert.Equal(t, int64(50), out)
	uassert.Equal(t, int64(300), v.Held())
	uassert.Equal(t, int64(150), v.Supply())

	// alice redeems 100 shares of 150 against 300 escrowed: 200 back, on a
	// 100 deposit. bob's donation went to whoever was holding.
	back, err := v.Unwrap(0, cur, alice, 100)
	urequire.NoError(t, err)
	uassert.Equal(t, int64(200), back)
	uassert.Equal(t, int64(1_100), under.BalanceOf(alice))

	// carl is made whole, and the pool closes empty.
	back, err = v.Unwrap(0, cur, carl, 50)
	urequire.NoError(t, err)
	uassert.Equal(t, int64(100), back)
	uassert.Equal(t, int64(0), v.Held())
	uassert.Equal(t, int64(0), v.Supply())
	uassert.True(t, v.Solvent())
}

// Fee over Pool: the haircut is not paid out, it is left behind, so the people
// still holding are the ones who collect it.
func TestFeeOverPoolPaysTheHolders(cur realm, t *testing.T) {
	under, led := mintUnder(cur, t, alice, bob)

	testing.SetRealm(testing.NewCodeRealm(wrapPath))
	v := NewVault(under, Fee{Base: Pool{}, WrapBPS: 0, UnwrapBPS: 1_000}, "Sticky Under", "fUND", 4, 0, cur)
	approve(cur, t, led, alice, v.Home(), 1_000)
	approve(cur, t, led, bob, v.Home(), 1_000)

	_, err := v.Wrap(0, cur, alice, 500)
	urequire.NoError(t, err)
	_, err = v.Wrap(0, cur, bob, 500)
	urequire.NoError(t, err)
	uassert.Equal(t, int64(1_000), v.Supply())

	// alice leaves and pays 10% on the way out: 500 - 50.
	back, err := v.Unwrap(0, cur, alice, 500)
	urequire.NoError(t, err)
	uassert.Equal(t, int64(450), back)

	// bob stayed, and the 50 alice left behind is now his.
	uassert.Equal(t, int64(550), v.Held())
	uassert.Equal(t, int64(500), v.Supply())
	back, err = v.Unwrap(0, cur, bob, 500)
	urequire.NoError(t, err)
	uassert.Equal(t, int64(495), back) // 550 pro rata, minus the same 10%
	uassert.Equal(t, int64(55), v.Held())
}

// Two vaults over the same underlying share one escrow account, so Held() is
// the only thing that keeps them apart. Pin that they do.
func TestTwoVaultsShareOneEscrowAccount(cur realm, t *testing.T) {
	under, led := mintUnder(cur, t, alice)

	testing.SetRealm(testing.NewCodeRealm(wrapPath))
	a := NewVault(under, OneToOne{}, "Vault A", "vA", 4, 0, cur)
	b := NewVault(under, OneToOne{}, "Vault B", "vB", 4, 1, cur)
	uassert.Equal(t, a.Home().String(), b.Home().String())
	approve(cur, t, led, alice, a.Home(), 1_000)

	_, err := a.Wrap(0, cur, alice, 300)
	urequire.NoError(t, err)
	_, err = b.Wrap(0, cur, alice, 200)
	urequire.NoError(t, err)

	uassert.Equal(t, int64(300), a.Held())
	uassert.Equal(t, int64(200), b.Held())
	// Custody is realm-wide: it sees both.
	uassert.Equal(t, int64(500), a.Custody())
	uassert.Equal(t, int64(500), b.Custody())

	// Vault B refuses to release more than it took in, even though the
	// account it draws on holds A's escrow too. Without the per-vault
	// counter this is exactly where one vault would eat the other's.
	_, err = b.Unwrap(0, cur, alice, 201)
	uassert.ErrorIs(t, err, ErrUnbacked)
	uassert.Equal(t, int64(200), b.Held())
	uassert.Equal(t, int64(500), b.Custody())

	// Both still unwind cleanly and independently.
	_, err = b.Unwrap(0, cur, alice, 200)
	urequire.NoError(t, err)
	_, err = a.Unwrap(0, cur, alice, 300)
	urequire.NoError(t, err)
	uassert.Equal(t, int64(0), a.Custody())
	uassert.Equal(t, int64(1_000), under.BalanceOf(alice))
}

func TestMoveAndAllowance(cur realm, t *testing.T) {
	under, led := mintUnder(cur, t, alice)

	testing.SetRealm(testing.NewCodeRealm(wrapPath))
	v := NewVault(under, OneToOne{}, "Wrapped Under", "wUND", 4, 0, cur)
	approve(cur, t, led, alice, v.Home(), 1_000)
	_, err := v.Wrap(0, cur, alice, 600)
	urequire.NoError(t, err)

	urequire.NoError(t, v.Move(alice, bob, 100))
	uassert.Equal(t, int64(100), v.Token().BalanceOf(bob))
	uassert.ErrorIs(t, v.Move(alice, bob, 0), ErrInvalidAmount)

	urequire.NoError(t, v.Allow(alice, bob, 250))
	uassert.Equal(t, int64(250), v.Token().Allowance(alice, bob))
	urequire.NoError(t, v.MoveFrom(bob, alice, carl, 250))
	uassert.Equal(t, int64(250), v.Token().BalanceOf(carl))
	uassert.ErrorContains(t, v.MoveFrom(bob, alice, carl, 1), "insufficient allowance")
}

func TestNewVaultRejectsNilUnderlying(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewCodeRealm(wrapPath))
	uassert.PanicsContains(t, cur, "nil underlying token", func() {
		NewVault(nil, OneToOne{}, "Broken", "BRK", 4, 0, cur)
	})
}

func TestNilPolicyMeansOneToOne(cur realm, t *testing.T) {
	under, _ := mintUnder(cur, t)

	testing.SetRealm(testing.NewCodeRealm(wrapPath))
	v := NewVault(under, nil, "Wrapped Under", "wUND", 4, 0, cur)
	uassert.Equal(t, "1:1", v.Policy().Name())
}

func TestSummaryReportsSolvency(cur realm, t *testing.T) {
	under, led := mintUnder(cur, t, alice)

	testing.SetRealm(testing.NewCodeRealm(wrapPath))
	v := NewVault(under, OneToOne{}, "Wrapped Under", "wUND", 4, 0, cur)
	approve(cur, t, led, alice, v.Home(), 1_000)
	_, err := v.Wrap(0, cur, alice, 250)
	urequire.NoError(t, err)

	want := "**Wrapped Under** (wUND) - 1:1 wrapper over UND\n\n" +
		"- wrapped supply: 250\n" +
		"- escrowed underlying: 250\n" +
		"- realm custody: 250\n" +
		"- solvent: yes\n"
	uassert.Equal(t, want, v.Summary())
}
