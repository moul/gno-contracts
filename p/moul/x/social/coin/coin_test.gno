package coin

import (
	"strings"
	"testing"

	"gno.land/p/nt/seqid/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

var fullPolicy = Policy{
	Mint:  "1 per distinct replier",
	Sink:  "burned to pin a thread",
	Buyer: "anyone who wants placement",
}

// newTestCoin builds a Coin from a test. The same-realm cross promotes the
// test's EOA-origin cur into a code realm frame, which is what grc20.NewToken
// requires: it is the shape grc20's own tests use (vendor/.../token_test.gno).
func newTestCoin(t *testing.T, policy Policy, id seqid.ID, rlm realm) (c *Coin) {
	t.Helper()
	func(cur realm) {
		c = New("Test Points", "TEST", 0, id, policy, 0, cur)
	}(cross(rlm))
	return
}

func TestPolicyValid(t *testing.T) {
	tests := []struct {
		name string
		p    Policy
		want bool
	}{
		{"complete", fullPolicy, true},
		{"no mint rule", Policy{Sink: "s", Buyer: "b"}, false},
		{"no sink", Policy{Mint: "m", Buyer: "b"}, false},
		{"no buyer", Policy{Mint: "m", Sink: "s"}, false},
		{"empty", Policy{}, false},
	}
	for _, tt := range tests {
		uassert.Equal(t, tt.want, tt.p.Valid(), tt.name)
	}
}

// New's refusal is asserted with AbortsContains and not PanicsContains: the
// constructor runs behind a same-realm cross (the frame grc20.NewToken
// requires), and a panic raised across a crossing call is an abort that no
// recover() in the caller can catch.
func TestNewRefusesAnIncompletePolicy(cur realm, t *testing.T) {
	uassert.AbortsContains(t, cur, "mint rule, a sink and a buyer", func() {
		newTestCoin(t, Policy{Mint: "m", Sink: "s"}, 0, cur)
	})
}

func TestEarnAndSpendMoveSupplyInOppositeDirections(cur realm, t *testing.T) {
	c := newTestCoin(t, fullPolicy, 1, cur)
	alice := testutils.TestAddress("alice")

	c.Earn(alice, 10)
	uassert.Equal(t, int64(10), c.BalanceOf(alice))
	uassert.Equal(t, int64(10), c.Supply())

	c.Spend(alice, 4)
	uassert.Equal(t, int64(6), c.BalanceOf(alice))
	uassert.Equal(t, int64(6), c.Supply())

	// The flows stay visible after the fact, which the supply alone cannot
	// show: 6 in supply could be 6 earned and nothing burned.
	uassert.Equal(t, int64(10), c.Earned())
	uassert.Equal(t, int64(4), c.Spent())
}

func TestEarnOfNothingIsANoOp(cur realm, t *testing.T) {
	c := newTestCoin(t, fullPolicy, 2, cur)
	alice := testutils.TestAddress("alice")

	c.Earn(alice, 0)
	c.Earn(alice, -5)
	uassert.Equal(t, int64(0), c.Supply())
	uassert.Equal(t, int64(0), c.Earned())
	uassert.Equal(t, 0, c.Holders())
}

func TestSpendNamesBothNumbersWhenShort(cur realm, t *testing.T) {
	c := newTestCoin(t, fullPolicy, 3, cur)
	alice := testutils.TestAddress("alice")
	c.Earn(alice, 2)

	uassert.PanicsContains(t, cur, "balance 2 is short of 5", func() {
		c.Spend(alice, 5)
	})
	uassert.PanicsContains(t, cur, "must be positive", func() {
		c.Spend(alice, 0)
	})
	uassert.Equal(t, int64(2), c.BalanceOf(alice))
}

func TestRenderCarriesTheThreeDeclarations(cur realm, t *testing.T) {
	c := newTestCoin(t, fullPolicy, 4, cur)
	c.Earn(testutils.TestAddress("alice"), 7)
	c.Spend(testutils.TestAddress("alice"), 3)

	out := c.Render()
	for _, want := range []string{
		"Test Points",
		"TEST",
		fullPolicy.Mint,
		fullPolicy.Sink,
		fullPolicy.Buyer,
	} {
		uassert.True(t, strings.Contains(out, want), "render is missing "+want)
	}
	// 4 in supply, 7 earned, 3 burned, 1 holder.
	uassert.True(t, strings.Contains(out, "| 4 | 7 | 3 | 1 |"), "render is missing the flow row: "+out)
}

func TestTokenIsAnOrdinaryGRC20(cur realm, t *testing.T) {
	c := newTestCoin(t, fullPolicy, 5, cur)
	alice := testutils.TestAddress("alice")
	c.Earn(alice, 3)

	tok := c.Token()
	urequire.False(t, tok == nil, "token should not be nil")
	uassert.Equal(t, "TEST", tok.GetSymbol())
	uassert.Equal(t, int64(3), tok.TotalSupply())
	uassert.Equal(t, int64(3), tok.BalanceOf(alice))
}
