package envelope

import (
	"chain"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

const (
	coin  = "/gno.land/r/moul/x/moultest/v0:moultest"
	other = "ugnot"
)

func pay(coins ...chain.Coin) {
	testing.SetOriginSend(chain.NewCoins(coins...))
}

func TestReadsAnEmptyEnvelope(cur realm, t *testing.T) {
	pay()
	uassert.True(t, IsEmpty())
	uassert.Equal(t, int64(0), Amount(coin))
	uassert.Equal(t, 0, len(All()))
	uassert.PanicsContains(t, cur, "must be paid", func() { Require(coin) })
}

func TestReadsAPaidEnvelope(cur realm, t *testing.T) {
	pay(chain.NewCoin(coin, 250))
	uassert.False(t, IsEmpty())
	uassert.Equal(t, int64(250), Amount(coin))
	uassert.Equal(t, int64(250), Require(coin))
	uassert.Equal(t, int64(0), Amount(other), "a denom that did not arrive reads zero")
	pay()
}

func TestFloorsAndPrices(cur realm, t *testing.T) {
	pay(chain.NewCoin(coin, 100))

	uassert.Equal(t, int64(100), RequireAtLeast(coin, 100), "the floor is inclusive")
	uassert.Equal(t, int64(100), RequireAtLeast(coin, 99))
	uassert.PanicsContains(t, cur, "costs at least 101", func() { RequireAtLeast(coin, 101) })

	uassert.Equal(t, int64(100), RequireExactly(coin, 100))
	uassert.PanicsContains(t, cur, "costs exactly 99", func() { RequireExactly(coin, 99) },
		"being overpaid is refused too, not quietly kept")
	uassert.PanicsContains(t, cur, "costs exactly 101", func() { RequireExactly(coin, 101) })
	pay()
}

func TestOnlyRefusesAMixedEnvelope(cur realm, t *testing.T) {
	pay(chain.NewCoin(coin, 100))
	uassert.Equal(t, int64(100), Only(coin))

	pay(chain.NewCoin(coin, 100), chain.NewCoin(other, 7))
	uassert.Equal(t, int64(100), Amount(coin), "the mixed envelope still reads fine")
	uassert.Equal(t, int64(7), Amount(other))
	uassert.PanicsContains(t, cur, "also carried 7ugnot", func() { Only(coin) })

	// Only still requires the denom it was asked about, mixed or not.
	pay(chain.NewCoin(other, 7))
	uassert.PanicsContains(t, cur, "must be paid", func() { Only(coin) })
	pay()
}

func TestRequireNamesTheFlagToFix(cur realm, t *testing.T) {
	// The abort is the realm's user interface at the moment somebody got it
	// wrong, so it carries the flag and the denom, not a status code.
	pay()
	uassert.PanicsContains(t, cur, "-send <amount>"+coin, func() { Require(coin) })
}
