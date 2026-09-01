package fraction

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func mk(t *testing.T, n, d int64) Fraction {
	t.Helper()
	f, err := New(n, d)
	uassert.NoError(t, err)
	return f
}

func TestNewReduces(t *testing.T) {
	uassert.Equal(t, "1/2", mk(t, 2, 4).String())
	uassert.Equal(t, "2", mk(t, 6, 3).String())
	uassert.Equal(t, "0", mk(t, 0, 5).String())
}

// The sign always lives in the numerator, so -1/2 and 1/-2 are the same value.
func TestSignNormalised(t *testing.T) {
	a := mk(t, 1, -2)
	uassert.Equal(t, "-1/2", a.String())
	uassert.True(t, a.Equal(mk(t, -1, 2)))
	uassert.True(t, mk(t, -2, -4).Equal(mk(t, 1, 2)))
}

func TestZeroDenominator(t *testing.T) {
	_, err := New(1, 0)
	uassert.ErrorIs(t, err, ErrZeroDenominator)
}

// The headline: exact arithmetic where floats would drift.
func TestExactThirds(t *testing.T) {
	third := mk(t, 1, 3)
	sum, ok := third.Add(third)
	uassert.True(t, ok)
	sum, ok = sum.Add(third)
	uassert.True(t, ok)
	uassert.Equal(t, "1", sum.String()) // exactly 1, not 0.9999…
}

func TestArithmetic(t *testing.T) {
	a, b := mk(t, 1, 2), mk(t, 1, 3)
	s, _ := a.Add(b)
	uassert.Equal(t, "5/6", s.String())
	d, _ := a.Sub(b)
	uassert.Equal(t, "1/6", d.String())
	m, _ := a.Mul(b)
	uassert.Equal(t, "1/6", m.String())
	q, _ := a.Div(b)
	uassert.Equal(t, "3/2", q.String())
	uassert.Equal(t, "-1/2", a.Neg().String())
}

func TestDivByZero(t *testing.T) {
	_, ok := mk(t, 1, 2).Div(Zero())
	uassert.False(t, ok)
}

// Overflow must be reported, never silently wrapped into a wrong answer.
func TestOverflowReported(t *testing.T) {
	big := Fraction{num: 1 << 62, den: 3}
	_, ok := big.Mul(Fraction{num: 1 << 62, den: 5})
	uassert.False(t, ok)
	_, ok2 := big.Add(Fraction{num: 1 << 62, den: 7})
	uassert.False(t, ok2)
}

// Comparison is exact: cross-multiplication, never a decimal detour.
func TestCmp(t *testing.T) {
	uassert.Equal(t, -1, mk(t, 1, 3).Cmp(mk(t, 1, 2)))
	uassert.Equal(t, 1, mk(t, 2, 3).Cmp(mk(t, 1, 2)))
	uassert.Equal(t, 0, mk(t, 2, 4).Cmp(mk(t, 1, 2)))
	// 1/3 vs 33333/100000 — a decimal comparison at 5 places would call these equal
	uassert.Equal(t, 1, mk(t, 1, 3).Cmp(mk(t, 33333, 100000)))
}

func TestDecimal(t *testing.T) {
	uassert.Equal(t, "0.333", Decimal(mk(t, 1, 3), 3))
	uassert.Equal(t, "0.5", Decimal(mk(t, 1, 2), 1))
	uassert.Equal(t, "1", Decimal(mk(t, 3, 2), 0)) // truncates toward zero
	uassert.Equal(t, "-0.333", Decimal(mk(t, -1, 3), 3))
	uassert.Equal(t, "2.000", Decimal(Int(2), 3))
	uassert.Equal(t, "0", Decimal(Zero(), 0))
}

// The zero value must behave as 0/1 rather than dividing by zero.
func TestZeroValueUsable(t *testing.T) {
	var f Fraction
	uassert.Equal(t, int64(1), f.Den())
	uassert.True(t, f.IsZero())
	uassert.Equal(t, "0", f.String())
	s, ok := f.Add(Int(1))
	uassert.True(t, ok)
	uassert.Equal(t, "1", s.String())
}
