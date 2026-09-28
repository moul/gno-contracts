package xmath

import "math/bits"

// maxInt64 is the largest int64. Unexported and spelled out because xmath
// already exports MaxInt64 as the max-of-two helper, and a constant sharing
// that name would shadow it.
const maxInt64 = int64(9223372036854775807)

// MulDiv returns a*b/c computed through a 128-bit intermediate, so the product
// does not have to fit in an int64. It is the proportional-share calculation:
// "this account's cut of the pot", "this stake's slice of the rewards".
//
// The naive a*b/c silently wraps when a*b exceeds an int64, and it wraps to a
// plausible-looking number rather than to an obvious one, which is how a payout
// split leaks money without anything failing. Ten realms deployed on gnoland-1
// carry their own copy of this function for exactly that reason, and every one
// of them reaches for math/bits the same way.
//
// MulDiv panics rather than returning a wrong number:
//
//   - a or b negative, or c at or below zero: the domain is unsigned ratios,
//     and a negative share is a caller bug, not a value to propagate.
//   - the quotient not fitting in an int64.
//
// Rounding is toward zero, like integer division. See [MulDivUp] when the
// remainder must favour the payer instead.
func MulDiv(a, b, c int64) int64 {
	if a < 0 || b < 0 {
		panic("xmath: MulDiv on a negative operand")
	}
	if c <= 0 {
		panic("xmath: MulDiv by a non-positive denominator")
	}
	hi, lo := bits.Mul64(uint64(a), uint64(b))
	if hi >= uint64(c) {
		panic("xmath: MulDiv quotient overflows int64")
	}
	q, _ := bits.Div64(hi, lo, uint64(c))
	if q > uint64(maxInt64) {
		panic("xmath: MulDiv quotient overflows int64")
	}
	return int64(q)
}

// MulDivUp is [MulDiv] rounding away from zero when the division is not exact.
//
// Which way to round is a money question, not a style one: rounding a fee down
// and a payout up is how a pool pays out more than it holds. Use MulDiv for
// what someone receives and MulDivUp for what someone owes.
func MulDivUp(a, b, c int64) int64 {
	q := MulDiv(a, b, c)
	hi, lo := bits.Mul64(uint64(a), uint64(b))
	_, rem := bits.Div64(hi, lo, uint64(c))
	if rem != 0 {
		if q == maxInt64 {
			panic("xmath: MulDivUp quotient overflows int64")
		}
		q++
	}
	return q
}

