// Package fractiondemo is a small gnoweb demo of the exact rational arithmetic
// provided by the [p/moul/x/daily/fraction](/p/moul/x/daily/fraction/v1)
// library: it shows thirds summing to exactly one, and a comparison that a
// decimal detour would get wrong.
//
// It contains no arithmetic of its own. Stateless, so Render is deterministic.
package fractiondemo

import (
	"strings"

	"gno.land/p/moul/x/daily/fraction/v1"
)

// Render renders the demo for gnoweb.
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# Fractions\n\n")
	b.WriteString("Exact rational arithmetic, demoing the ")
	b.WriteString("[`p/moul/x/daily/fraction`](/p/moul/x/daily/fraction/v1) library.\n\n")

	third, _ := fraction.New(1, 3)
	sum, _ := third.Add(third)
	sum, _ = sum.Add(third)

	b.WriteString("## A third, three times\n\n")
	b.WriteString("`1/3 + 1/3 + 1/3` = **")
	b.WriteString(sum.String())
	b.WriteString("**, exactly — not 0.9999…\n\n")
	b.WriteString("As a decimal it is only ever an approximation: `")
	b.WriteString(fraction.Decimal(third, 10))
	b.WriteString("`\n")

	half, _ := fraction.New(1, 2)
	b.WriteString("\n## Arithmetic\n\n| expression | result |\n|---|---|\n")
	add, _ := half.Add(third)
	sub, _ := half.Sub(third)
	mul, _ := half.Mul(third)
	div, _ := half.Div(third)
	row(&b, "1/2 + 1/3", add.String())
	row(&b, "1/2 - 1/3", sub.String())
	row(&b, "1/2 × 1/3", mul.String())
	row(&b, "1/2 ÷ 1/3", div.String())

	approx, _ := fraction.New(33333, 100000)
	b.WriteString("\n## Exact comparison\n\n")
	b.WriteString("`1/3` vs `33333/100000` — identical to five decimal places, ")
	b.WriteString("yet the library still knows which is larger: **")
	if third.Cmp(approx) > 0 {
		b.WriteString("1/3 is greater")
	} else {
		b.WriteString("33333/100000 is greater or equal")
	}
	b.WriteString("**\n\n")
	b.WriteString("> Comparison cross-multiplies, so it never takes a decimal detour. ")
	b.WriteString("There are no floats here: on a chain, an answer that depends on ")
	b.WriteString("rounding is a consensus bug.\n")
	return b.String()
}

func row(b *strings.Builder, expr, res string) {
	b.WriteString("| `")
	b.WriteString(expr)
	b.WriteString("` | `")
	b.WriteString(res)
	b.WriteString("` |\n")
}
