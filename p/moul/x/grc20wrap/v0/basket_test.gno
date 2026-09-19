package grc20wrap

import (
	"testing"

	"gno.land/p/nt/grc20/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

const (
	pairPath   = "gno.land/r/test/pair"
	basketPath = "gno.land/r/test/basket"
)

// mintPair issues two independent tokens from one foreign realm and funds the
// holders with both.
func mintPair(cur realm, t *testing.T, red, blue int64, funded ...address) (*grc20.Token, *grc20.PrivateLedger, *grc20.Token, *grc20.PrivateLedger) {
	t.Helper()
	testing.SetRealm(testing.NewCodeRealm(pairPath))
	rt, rl := grc20.NewToken("Red", "RED", 4, 0, cur)
	bt, bl := grc20.NewToken("Blue", "BLUE", 4, 1, cur)
	for _, a := range funded {
		urequire.NoError(t, rl.Mint(a, red))
		urequire.NoError(t, bl.Mint(a, blue))
	}
	return rt, rl, bt, bl
}

func TestFuseAndDefuse(cur realm, t *testing.T) {
	red, redLed, blue, blueLed := mintPair(cur, t, 1_000, 1_000, alice)

	testing.SetRealm(testing.NewCodeRealm(basketPath))
	b := NewBasket(
		[]*grc20.Token{red, blue},
		[]int64{1, 2},
		"Purple", "PURPLE", 4, 0, cur,
	)
	approve(cur, t, redLed, alice, b.Home(), 1_000)
	approve(cur, t, blueLed, alice, b.Home(), 1_000)

	urequire.NoError(t, b.Fuse(0, cur, alice, 10))
	uassert.Equal(t, int64(10), b.Token().BalanceOf(alice))
	uassert.Equal(t, int64(990), red.BalanceOf(alice))
	uassert.Equal(t, int64(980), blue.BalanceOf(alice))

	_, per, held := b.Leg(0)
	uassert.Equal(t, int64(1), per)
	uassert.Equal(t, int64(10), held)
	_, per, held = b.Leg(1)
	uassert.Equal(t, int64(2), per)
	uassert.Equal(t, int64(20), held)
	uassert.True(t, b.Solvent())

	urequire.NoError(t, b.Defuse(0, cur, alice, 4))
	uassert.Equal(t, int64(6), b.Token().TotalSupply())
	uassert.Equal(t, int64(994), red.BalanceOf(alice))
	uassert.Equal(t, int64(988), blue.BalanceOf(alice))

	// Out entirely: the basket closes empty on both legs.
	urequire.NoError(t, b.Defuse(0, cur, alice, 6))
	uassert.Equal(t, int64(0), b.Token().TotalSupply())
	_, _, held = b.Leg(0)
	uassert.Equal(t, int64(0), held)
	_, _, held = b.Leg(1)
	uassert.Equal(t, int64(0), held)
	uassert.Equal(t, int64(1_000), red.BalanceOf(alice))
	uassert.Equal(t, int64(1_000), blue.BalanceOf(alice))
}

// The whole basket is priced before the first transfer, so being short on the
// SECOND leg leaves the first one untouched. Without the pre-pass this is where
// a partially-applied mint would come from.
func TestFuseChecksEveryLegBeforeMovingAny(cur realm, t *testing.T) {
	red, redLed, blue, blueLed := mintPair(cur, t, 1_000, 10, alice)

	testing.SetRealm(testing.NewCodeRealm(basketPath))
	b := NewBasket(
		[]*grc20.Token{red, blue},
		[]int64{1, 2},
		"Purple", "PURPLE", 4, 0, cur,
	)
	approve(cur, t, redLed, alice, b.Home(), 1_000)
	approve(cur, t, blueLed, alice, b.Home(), 1_000)

	// 100 units needs 100 RED (fine) and 200 BLUE (alice has 10).
	uassert.ErrorIs(t, b.Fuse(0, cur, alice, 100), ErrShortBalance)
	uassert.Equal(t, int64(1_000), red.BalanceOf(alice))
	uassert.Equal(t, int64(0), b.Token().TotalSupply())

	// Same for a missing allowance on the second leg only.
	approve(cur, t, blueLed, alice, b.Home(), 0)
	urequire.NoError(t, blueLed.Mint(alice, 1_000))
	uassert.ErrorIs(t, b.Fuse(0, cur, alice, 5), ErrShortAllowance)
	uassert.Equal(t, int64(1_000), red.BalanceOf(alice))
	uassert.Equal(t, int64(0), b.Token().TotalSupply())
}

func TestDefuseStopsAtTheBalance(cur realm, t *testing.T) {
	red, redLed, blue, blueLed := mintPair(cur, t, 1_000, 1_000, alice, bob)

	testing.SetRealm(testing.NewCodeRealm(basketPath))
	b := NewBasket(
		[]*grc20.Token{red, blue},
		[]int64{1, 1},
		"Purple", "PURPLE", 4, 0, cur,
	)
	for _, a := range []address{alice, bob} {
		approve(cur, t, redLed, a, b.Home(), 1_000)
		approve(cur, t, blueLed, a, b.Home(), 1_000)
	}

	urequire.NoError(t, b.Fuse(0, cur, alice, 50))
	uassert.ErrorContains(t, b.Defuse(0, cur, bob, 1), "insufficient balance")
	uassert.ErrorIs(t, b.Defuse(0, cur, alice, 0), ErrInvalidAmount)
	_, _, held := b.Leg(0)
	uassert.Equal(t, int64(50), held)
}

func TestNewBasketRejectsBadLegs(cur realm, t *testing.T) {
	red, _, blue, _ := mintPair(cur, t, 1_000, 1_000)

	testing.SetRealm(testing.NewCodeRealm(basketPath))

	// A one-leg basket is a Vault; say so instead of pretending.
	uassert.PanicsContains(t, cur, "at least two legs", func() {
		NewBasket([]*grc20.Token{red}, []int64{1}, "X", "X", 4, 0, cur)
	})
	// Mismatched slices.
	uassert.PanicsContains(t, cur, "at least two legs", func() {
		NewBasket([]*grc20.Token{red, blue}, []int64{1}, "X", "X", 4, 0, cur)
	})
	// A zero part would let a leg be minted for free.
	uassert.PanicsContains(t, cur, "at least two legs", func() {
		NewBasket([]*grc20.Token{red, blue}, []int64{1, 0}, "X", "X", 4, 0, cur)
	})
	// The same token twice is two accountings of one balance.
	uassert.PanicsContains(t, cur, "at least two legs", func() {
		NewBasket([]*grc20.Token{red, red}, []int64{1, 1}, "X", "X", 4, 0, cur)
	})
	uassert.PanicsContains(t, cur, "nil underlying token", func() {
		NewBasket([]*grc20.Token{red, nil}, []int64{1, 1}, "X", "X", 4, 0, cur)
	})
}

func TestBasketMoveAndAllowance(cur realm, t *testing.T) {
	red, redLed, blue, blueLed := mintPair(cur, t, 1_000, 1_000, alice)

	testing.SetRealm(testing.NewCodeRealm(basketPath))
	b := NewBasket(
		[]*grc20.Token{red, blue},
		[]int64{1, 1},
		"Purple", "PURPLE", 4, 0, cur,
	)
	approve(cur, t, redLed, alice, b.Home(), 1_000)
	approve(cur, t, blueLed, alice, b.Home(), 1_000)
	urequire.NoError(t, b.Fuse(0, cur, alice, 100))

	urequire.NoError(t, b.Move(alice, bob, 40))
	uassert.Equal(t, int64(40), b.Token().BalanceOf(bob))
	urequire.NoError(t, b.Allow(alice, bob, 30))
	urequire.NoError(t, b.MoveFrom(bob, alice, carl, 30))
	uassert.Equal(t, int64(30), b.Token().BalanceOf(carl))
	uassert.ErrorIs(t, b.MoveFrom(bob, alice, carl, 0), ErrInvalidAmount)

	// bob holds meta units he never minted, and can still split them.
	urequire.NoError(t, b.Defuse(0, cur, bob, 40))
	uassert.Equal(t, int64(40), red.BalanceOf(bob))
	uassert.Equal(t, int64(40), blue.BalanceOf(bob))
}

func TestBasketSummary(cur realm, t *testing.T) {
	red, redLed, blue, blueLed := mintPair(cur, t, 1_000, 1_000, alice)

	testing.SetRealm(testing.NewCodeRealm(basketPath))
	b := NewBasket(
		[]*grc20.Token{red, blue},
		[]int64{1, 2},
		"Purple", "PURPLE", 4, 0, cur,
	)
	approve(cur, t, redLed, alice, b.Home(), 1_000)
	approve(cur, t, blueLed, alice, b.Home(), 1_000)
	urequire.NoError(t, b.Fuse(0, cur, alice, 7))

	want := "**Purple** (PURPLE) - meta-token over 2 legs\n\n" +
		"- meta supply: 7\n" +
		"- leg RED: 1 per unit, 7 escrowed\n" +
		"- leg BLUE: 2 per unit, 14 escrowed\n" +
		"- solvent: yes\n"
	uassert.Equal(t, want, b.Summary())
}
