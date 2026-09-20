package grc20wrap

import (
	"math"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// Every policy here is stateless, so it prices correctly against a nil vault.
// Pool is the one that reads the vault, and it is covered end to end in
// TestPoolSharesAppreciate.
func TestStatelessRates(t *testing.T) {
	cases := []struct {
		name      string
		pol       Policy
		wrapIn    int64
		wrapOut   int64
		unwrapIn  int64
		unwrapOut int64
	}{
		{"one to one", OneToOne{}, 7, 7, 7, 7},
		{"kilo", Ratio{Num: 1_000, Den: 1}, 7, 7_000, 7_000, 7},
		{"kilo truncates on the way out", Ratio{Num: 1_000, Den: 1}, 1, 1_000, 2_500, 2},
		{"milli", Ratio{Num: 1, Den: 1_000}, 7_000, 7, 7, 7_000},
		{"two for three", Ratio{Num: 2, Den: 3}, 9, 6, 6, 9},
		{"soulbound keeps its base rate", Soulbound{Base: Ratio{Num: 2, Den: 1}}, 5, 10, 10, 5},
		{"soulbound with no base is 1:1", Soulbound{}, 5, 5, 5, 5},
		{"one percent both ways", Fee{WrapBPS: 100, UnwrapBPS: 100}, 1_000, 990, 1_000, 990},
		{"a haircut under one unit rounds to nothing", Fee{WrapBPS: 100}, 55, 55, 55, 55},
	}

	for _, tc := range cases {
		got, err := tc.pol.WrapRate(nil, tc.wrapIn)
		uassert.NoError(t, err, tc.name)
		uassert.Equal(t, tc.wrapOut, got, tc.name+" (wrap)")

		got, err = tc.pol.UnwrapRate(nil, tc.unwrapIn)
		uassert.NoError(t, err, tc.name)
		uassert.Equal(t, tc.unwrapOut, got, tc.name+" (unwrap)")
	}
}

func TestRateErrors(t *testing.T) {
	cases := []struct {
		name      string
		pol       Policy
		in        int64
		wrapErr   error
		unwrapErr error
	}{
		{"zero numerator", Ratio{Num: 0, Den: 1}, 5, ErrBadRatio, ErrBadRatio},
		{"negative denominator", Ratio{Num: 2, Den: -1}, 5, ErrBadRatio, ErrBadRatio},
		// Only the multiplying direction can overflow; the dividing one
		// just returns a very small number.
		{"overflowing numerator", Ratio{Num: math.MaxInt64, Den: 1}, 3, ErrOverflow, nil},
		{"basis points above 100%", Fee{WrapBPS: 10_001, UnwrapBPS: 10_001}, 100, ErrBadBPS, ErrBadBPS},
		{"negative basis points", Fee{WrapBPS: -1, UnwrapBPS: -1}, 100, ErrBadBPS, ErrBadBPS},
	}

	for _, tc := range cases {
		_, err := tc.pol.WrapRate(nil, tc.in)
		if tc.wrapErr == nil {
			uassert.NoError(t, err, tc.name+" (wrap)")
		} else {
			uassert.ErrorIs(t, err, tc.wrapErr, tc.name+" (wrap)")
		}

		_, err = tc.pol.UnwrapRate(nil, tc.in)
		if tc.unwrapErr == nil {
			uassert.NoError(t, err, tc.name+" (unwrap)")
		} else {
			uassert.ErrorIs(t, err, tc.unwrapErr, tc.name+" (unwrap)")
		}
	}
}

func TestPolicyNames(t *testing.T) {
	uassert.Equal(t, "1:1", OneToOne{}.Name())
	uassert.Equal(t, "1000:1", Ratio{Num: 1_000, Den: 1}.Name())
	uassert.Equal(t, "pool", Pool{}.Name())
	uassert.Equal(t, "soulbound/1:1", Soulbound{}.Name())
	uassert.Equal(t, "soulbound/pool", Soulbound{Base: Pool{}}.Name())
	uassert.Equal(t, "fee(0/100bps)/pool", Fee{Base: Pool{}, UnwrapBPS: 100}.Name())
}

func TestOnlySoulboundVetoes(t *testing.T) {
	uassert.NoError(t, OneToOne{}.CanMove(nil, alice, bob, 1))
	uassert.NoError(t, Ratio{Num: 1, Den: 1}.CanMove(nil, alice, bob, 1))
	uassert.NoError(t, Pool{}.CanMove(nil, alice, bob, 1))
	uassert.NoError(t, Fee{Base: Pool{}}.CanMove(nil, alice, bob, 1))
	uassert.ErrorIs(t, Soulbound{}.CanMove(nil, alice, bob, 1), ErrSoulbound)
	// A fee over a soulbound base inherits the veto.
	uassert.ErrorIs(t, Fee{Base: Soulbound{}}.CanMove(nil, alice, bob, 1), ErrSoulbound)
}
