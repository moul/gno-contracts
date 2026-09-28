package xmath

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestMulDiv(t *testing.T) {
	cases := []struct {
		name    string
		a, b, c int64
		want    int64
	}{
		{"exact", 10, 3, 5, 6},
		{"rounds toward zero", 10, 1, 3, 3},
		{"identity", 7, 1, 1, 7},
		{"zero numerator", 0, 99, 7, 0},
		{"half of a pot", 1000000, 50, 100, 500000},
		{"one basis point", 1000000, 1, 10000, 100},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			uassert.Equal(t, tc.want, MulDiv(tc.a, tc.b, tc.c))
		})
	}
}

// TestMulDivSurvivesAnIntermediateThatDoesNotFit is the whole point. The naive
// a*b/c computes a*b first, which wraps past the int64 maximum and wraps to a
// plausible number rather than an obvious one. Through a 128-bit intermediate
// the answer is exact.
func TestMulDivSurvivesAnIntermediateThatDoesNotFit(t *testing.T) {
	// A variable, not a const: gno rejects a constant expression that
	// overflows at compile time, and the point here is the runtime wrap.
	big := int64(1) << 62 // 4611686018427387904
	four := int64(4)

	// big*4 overflows int64; big*4/8 is big/2 and fits comfortably.
	uassert.Equal(t, big/2, MulDiv(big, four, 8))

	// The naive form, computed here so the test shows what it would have done
	// rather than asserting it in prose.
	naive := (big * four) / 8
	uassert.NotEqual(t, big/2, naive)

	// big*4 is exactly 2^64, so it wraps to 0 and the naive form answers 0 for
	// a share that is actually 2305843009213693952. Measured, not assumed: the
	// first version of this test asserted the wrap went negative, which is the
	// intuition and is wrong for this input.
	uassert.Equal(t, int64(0), naive)
}

func TestMulDivRefusesRatherThanReturningAWrongNumber(t *testing.T) {
	big := int64(1) << 62
	cases := []struct {
		name    string
		a, b, c int64
		msg     string
	}{
		{"negative a", -1, 2, 3, "xmath: MulDiv on a negative operand"},
		{"negative b", 1, -2, 3, "xmath: MulDiv on a negative operand"},
		{"zero denominator", 1, 2, 0, "xmath: MulDiv by a non-positive denominator"},
		{"negative denominator", 1, 2, -3, "xmath: MulDiv by a non-positive denominator"},
		{"quotient too large", big, 8, 2, "xmath: MulDiv quotient overflows int64"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			defer func() {
				r := recover()
				if r == nil {
					t.Errorf("MulDiv(%d,%d,%d) did not panic", tc.a, tc.b, tc.c)
					return
				}
				uassert.Equal(t, tc.msg, r.(string))
			}()
			MulDiv(tc.a, tc.b, tc.c)
		})
	}
}

func TestMulDivUpRoundsAwayFromZero(t *testing.T) {
	cases := []struct {
		name    string
		a, b, c int64
		want    int64
	}{
		{"exact is unchanged", 10, 3, 5, 6},
		{"inexact rounds up", 10, 1, 3, 4},
		{"one short rounds up", 7, 1, 2, 4},
		{"zero stays zero", 0, 5, 3, 0},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			uassert.Equal(t, tc.want, MulDivUp(tc.a, tc.b, tc.c))
		})
	}
}

// TestRoundingDirectionIsTheMoneyQuestion states the invariant the two
// functions exist to give a caller: what is received never exceeds what is
// owed for the same ratio, so a pool cannot pay out more than it holds.
func TestRoundingDirectionIsTheMoneyQuestion(t *testing.T) {
	for _, n := range []int64{1, 2, 3, 7, 99, 1000001} {
		down := MulDiv(n, 1, 3)
		up := MulDivUp(n, 1, 3)
		if up < down {
			t.Errorf("MulDivUp(%d,1,3)=%d below MulDiv=%d", n, up, down)
		}
		if up-down > 1 {
			t.Errorf("MulDivUp(%d,1,3)=%d more than one above MulDiv=%d", n, up, down)
		}
	}
}
