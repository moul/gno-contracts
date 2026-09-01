# `gno.land/p/moul/x/daily/fraction/v1`

**Exact rational arithmetic** — `New`, `Int`, `Zero`, `Add`, `Sub`, `Mul`,
`Div`, `Neg`, `Cmp`, `Equal`, `String`, `Decimal`.

Values are `p/q` with `int64` numerator and denominator, always in lowest terms
with a positive denominator.

```go
import "gno.land/p/moul/x/daily/fraction/v1"

third, _ := fraction.New(1, 3)
sum, ok := third.Add(third)      // 2/3, ok
sum, ok = sum.Add(third)         // exactly 1 — not 0.9999…
fraction.Decimal(third, 5)       // "0.33333"
```

**This exists because there are no floats worth trusting on chain.** `0.1 + 0.2`
is not `0.3` in binary floating point, and a consensus system cannot afford an
answer that depends on rounding. A fraction is exact; it only becomes lossy at
the moment you ask for a decimal, and `Decimal` makes that moment explicit —
the caller chooses how much to lose and when.

**Overflow is reported, never wrapped.** Every operation returns `ok=false` on
`int64` overflow rather than silently producing a wrapped numerator, which would
be a wrong answer that looks perfectly fine.

`Cmp` cross-multiplies, so comparison is exact too: `1/3` and `33333/100000` are
identical to five decimal places, and it still knows which is larger.

The sign always lives in the numerator, so `1/-2` and `-1/2` are the same value.
The zero value of the type behaves as `0/1` rather than dividing by zero.

**Live demo:** [`r/moul/x/daily/fractiondemo`](https://github.com/moul/gno-contracts/tree/main/r/moul/x/daily/fractiondemo/v1)
· render it at [`/r/moul/x/daily/fractiondemo/v1`](https://gno.land/r/moul/x/daily/fractiondemo/v1).
