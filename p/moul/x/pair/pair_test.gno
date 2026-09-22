package pair

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// The pricing function, on its own, is the part worth pinning numerically: it
// is pure, it is where the 128-bit arithmetic lives, and every instance in the
// ecosystem runs this exact code.
func TestAmountOut(t *testing.T) {
	cases := []struct {
		name                    string
		in, resIn, resOut, want int64
	}{
		{"balanced pool, small trade", 1_000, 1_000_000, 1_000_000, 996},
		{"balanced pool, 1%", 10_000, 1_000_000, 1_000_000, 9_871},
		{"balanced pool, 10%", 100_000, 1_000_000, 1_000_000, 90_661},
		{"balanced pool, 50%", 500_000, 1_000_000, 1_000_000, 332_665},
		{"skewed pool", 100_000, 1_000_000, 4_000_000, 362_644},
		{"near drain", 1_000, 1, 1_000_000, 998_997},
		{"dust rounds to zero", 1, 1_000_000, 1_000_000, 0},
		{"reserves at the cap", MaxReserve / 2, MaxReserve / 2, MaxReserve, 4_604_758_097_518_382},
	}
	for _, tc := range cases {
		got := AmountOut(tc.in, tc.resIn, tc.resOut)
		uassert.Equal(t, tc.want, got, tc.name)
	}
}

// The fee is what stays behind: k must never decrease across a swap.
func TestConstantProductNeverRegresses(t *testing.T) {
	resIn, resOut := int64(1_000_000), int64(4_000_000)
	for _, in := range []int64{1, 1_000, 100_000, 999_999} {
		out := AmountOut(in, resIn, resOut)
		uassert.True(t, cmpProd(resIn+in, resOut-out, resIn, resOut) >= 0,
			"k must not regress")
	}
}

func TestAmountOutGuards(t *testing.T) {
	mustPanic(t, "pair: amountIn must be > 0", func() {
		AmountOut(0, 1_000, 1_000)
	})
	mustPanic(t, "pair: pair has an empty reserve", func() {
		AmountOut(1, 0, 1_000)
	})
	mustPanic(t, "pair: reserve above cap", func() {
		AmountOut(1, MaxReserve+1, 1_000)
	})
	mustPanic(t, "pair: reserve cap exceeded", func() {
		AmountOut(2, MaxReserve-1, 1_000)
	})
}

// mulDiv is the only place a 128-bit intermediate is required, and the only
// place bits.Div64 could panic. Both ends are asserted rather than argued.
func TestMulDiv(t *testing.T) {
	uassert.Equal(t, int64(2), mulDiv(4, 3, 6))
	uassert.Equal(t, int64(0), mulDiv(1, 1, 3), "floors")
	uassert.Equal(t, int64(4_611_686_018_427_387_903), mulDiv(9_223_372_036_854_775_807, 1, 2),
		"operands near MaxInt64 stay exact through the 128-bit path")

	mustPanic(t, "pair: division by a non-positive value", func() {
		mulDiv(1, 1, 0)
	})
	mustPanic(t, "pair: quotient overflows int64", func() {
		mulDiv(9_223_372_036_854_775_807, 9_223_372_036_854_775_807, 1)
	})
}

func TestCmpProd(t *testing.T) {
	uassert.Equal(t, 0, cmpProd(6, 7, 42, 1))
	uassert.Equal(t, -1, cmpProd(6, 6, 42, 1))
	uassert.Equal(t, 1, cmpProd(7, 7, 42, 1))
	// Both products exceed int64 and differ only in the low word.
	uassert.Equal(t, -1, cmpProd(4_000_000_000, 4_000_000_000, 4_000_000_000, 4_000_000_001))
}

// mustPanic is uassert.PanicsWithMessage without the realm argument: a pure
// package cannot produce a `cur` to hand it, since it can never declare a
// crossing function in the first place.
func mustPanic(t *testing.T, want string, f func()) {
	t.Helper()
	defer func() {
		r := recover()
		if r == nil {
			t.Errorf("expected panic %q, got none", want)
			return
		}
		got, ok := r.(string)
		if !ok {
			t.Errorf("expected a string panic %q, got %v", want, r)
			return
		}
		if got != want {
			t.Errorf("expected panic %q, got %q", want, got)
		}
	}()
	f()
}
