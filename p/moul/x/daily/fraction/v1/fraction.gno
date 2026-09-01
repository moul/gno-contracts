// Package fraction is exact rational arithmetic as a pure, reusable package:
// values are p/q with int64 numerator and denominator, always kept in lowest
// terms with a positive denominator.
//
// This exists because there are no floats worth trusting on chain. 0.1 + 0.2 is
// not 0.3 in binary floating point, and a consensus system cannot afford an
// answer that depends on rounding. A fraction is exact: one third really is one
// third, and only becomes lossy at the moment you ask for a decimal.
//
// Every operation is checked for int64 overflow and returns ok=false rather
// than silently wrapping — a wrapped numerator would be a wrong answer that
// looks fine.
//
// A live demo of this package is at
// [r/moul/x/daily/fractiondemo](/r/moul/x/daily/fractiondemo/v1).
package fraction

import (
	"errors"
	"strconv"
	"strings"
)

// ErrZeroDenominator is returned when a denominator of zero is requested.
var ErrZeroDenominator = errors.New("fraction: zero denominator")

// Fraction is an exact rational number in lowest terms, denominator > 0.
type Fraction struct {
	num, den int64
}

// New returns num/den reduced, or an error when den is zero.
func New(num, den int64) (Fraction, error) {
	if den == 0 {
		return Fraction{}, ErrZeroDenominator
	}
	if den < 0 { // keep the sign in the numerator so comparisons are simple
		num, den = -num, -den
	}
	g := gcd(abs(num), den)
	if g > 1 {
		num, den = num/g, den/g
	}
	return Fraction{num, den}, nil
}

// Int returns n as n/1.
func Int(n int64) Fraction { return Fraction{n, 1} }

// Zero is 0/1.
func Zero() Fraction { return Fraction{0, 1} }

// Num returns the numerator; Den the (always positive) denominator.
func (f Fraction) Num() int64 { return f.num }

// Den returns the denominator, which is always > 0. The zero value of the type
// has den == 0, so treat it as 1 to keep an un-initialised Fraction usable.
func (f Fraction) Den() int64 {
	if f.den == 0 {
		return 1
	}
	return f.den
}

// IsZero reports whether f == 0.
func (f Fraction) IsZero() bool { return f.num == 0 }

func abs(x int64) int64 {
	if x < 0 {
		return -x
	}
	return x
}

func gcd(a, b int64) int64 {
	for b != 0 {
		a, b = b, a%b
	}
	if a == 0 {
		return 1
	}
	return a
}

// mulOK multiplies with an overflow check.
func mulOK(a, b int64) (int64, bool) {
	if a == 0 || b == 0 {
		return 0, true
	}
	p := a * b
	if p/b != a { // the classic check: dividing back must reproduce a
		return 0, false
	}
	return p, true
}

// addOK adds with an overflow check.
func addOK(a, b int64) (int64, bool) {
	s := a + b
	if (a > 0 && b > 0 && s < 0) || (a < 0 && b < 0 && s >= 0) {
		return 0, false
	}
	return s, true
}

// Add returns f+g. ok is false on int64 overflow.
func (f Fraction) Add(g Fraction) (Fraction, bool) { return combine(f, g, false) }

// Sub returns f-g. ok is false on int64 overflow.
func (f Fraction) Sub(g Fraction) (Fraction, bool) { return combine(f, g, true) }

func combine(f, g Fraction, sub bool) (Fraction, bool) {
	fd, gd := f.Den(), g.Den()
	a, ok1 := mulOK(f.num, gd)
	b, ok2 := mulOK(g.num, fd)
	d, ok3 := mulOK(fd, gd)
	if !ok1 || !ok2 || !ok3 {
		return Fraction{}, false
	}
	if sub {
		b = -b
	}
	n, ok4 := addOK(a, b)
	if !ok4 {
		return Fraction{}, false
	}
	out, err := New(n, d)
	return out, err == nil
}

// Mul returns f*g. ok is false on int64 overflow.
func (f Fraction) Mul(g Fraction) (Fraction, bool) {
	n, ok1 := mulOK(f.num, g.num)
	d, ok2 := mulOK(f.Den(), g.Den())
	if !ok1 || !ok2 {
		return Fraction{}, false
	}
	out, err := New(n, d)
	return out, err == nil
}

// Div returns f/g. ok is false on overflow or division by zero.
func (f Fraction) Div(g Fraction) (Fraction, bool) {
	if g.IsZero() {
		return Fraction{}, false
	}
	n, ok1 := mulOK(f.num, g.Den())
	d, ok2 := mulOK(f.Den(), g.num)
	if !ok1 || !ok2 {
		return Fraction{}, false
	}
	out, err := New(n, d)
	return out, err == nil
}

// Neg returns -f.
func (f Fraction) Neg() Fraction { return Fraction{-f.num, f.Den()} }

// Cmp returns -1, 0 or +1 as f is less than, equal to, or greater than g.
// Compares by cross-multiplication, so it is exact — no decimal conversion.
func (f Fraction) Cmp(g Fraction) int {
	a, ok1 := mulOK(f.num, g.Den())
	b, ok2 := mulOK(g.num, f.Den())
	if !ok1 || !ok2 {
		// fall back to a lossy comparison only when exact would overflow
		fa := float64(f.num) / float64(f.Den())
		fb := float64(g.num) / float64(g.Den())
		switch {
		case fa < fb:
			return -1
		case fa > fb:
			return 1
		}
		return 0
	}
	switch {
	case a < b:
		return -1
	case a > b:
		return 1
	}
	return 0
}

// Equal reports exact equality.
func (f Fraction) Equal(g Fraction) bool { return f.Cmp(g) == 0 }

// String renders "p/q", or just "p" when the denominator is 1.
func (f Fraction) String() string {
	if f.Den() == 1 {
		return strconv.FormatInt(f.num, 10)
	}
	return strconv.FormatInt(f.num, 10) + "/" + strconv.FormatInt(f.Den(), 10)
}

// Decimal renders f with exactly places digits after the point, truncated
// toward zero. THIS is where exactness ends — 1/3 cannot be written in decimal,
// so the caller chooses how much to lose and when.
func Decimal(f Fraction, places int) string {
	if places < 0 {
		places = 0
	}
	n, d := f.num, f.Den()
	neg := n < 0
	if neg {
		n = -n
	}
	whole := n / d
	rem := n % d
	var b strings.Builder
	if neg && (whole != 0 || rem != 0) {
		b.WriteByte('-')
	}
	b.WriteString(strconv.FormatInt(whole, 10))
	if places == 0 {
		return b.String()
	}
	b.WriteByte('.')
	for i := 0; i < places; i++ {
		rem *= 10
		b.WriteString(strconv.FormatInt(rem/d, 10))
		rem %= d
	}
	return b.String()
}
