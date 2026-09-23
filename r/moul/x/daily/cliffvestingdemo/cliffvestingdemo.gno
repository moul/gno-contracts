// Package cliffvestingdemo is a small gnoweb demo of the vesting calculator
// provided by the [p/moul/x/daily/cliffvesting](/p/moul/x/daily/cliffvesting/v1)
// library: the cliff step, the linear ramp, integer rounding, and the two
// arithmetic bugs the library exists to avoid.
//
// It contains no vesting logic of its own and holds no coins. Stateless, so
// Render is deterministic, which is precisely what the library is for.
package cliffvestingdemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/x/daily/cliffvesting/v1"
)

// Render renders the demo for gnoweb.
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# Cliff Vesting\n\n")
	b.WriteString("A pure vesting calculator, demoing the ")
	b.WriteString("[`p/moul/x/daily/cliffvesting`](/p/moul/x/daily/cliffvesting/v1) library.\n\n")

	// 1200 tokens over 12 months, 3-month cliff.
	s, err := cliffvesting.New(1200, 0, 3, 12)
	if err != nil {
		return "error: " + err.Error()
	}

	b.WriteString("## A 12-month grant with a 3-month cliff\n\n")
	b.WriteString("`1200` tokens, `Start = 0`, `Cliff = 3`, `End = 12`.\n\n")
	b.WriteString("| month | vested | unvested | % |\n|---|---|---|---|\n")
	for m := int64(0); m <= 12; m++ {
		note := ""
		switch m {
		case 2:
			note = " ← nothing yet"
		case 3:
			note = " ← **cliff**"
		case 12:
			note = " ← fully vested"
		}
		b.WriteString("| " + strconv.FormatInt(m, 10) + " | " +
			strconv.FormatInt(s.Vested(m), 10) + " | " +
			strconv.FormatInt(s.Unvested(m), 10) + " | " +
			strconv.FormatInt(s.PercentVested(m), 10) + "%" + note + " |\n")
	}

	b.WriteString("\nThe cliff is a **step, not a ramp**: at month 3 a quarter of the term ")
	b.WriteString("has elapsed, so `")
	b.WriteString(strconv.FormatInt(s.CliffAmount(), 10))
	b.WriteString("` tokens unlock at once. After that it accrues linearly.\n\n")

	b.WriteString("## Claiming\n\n")
	b.WriteString("The library tracks no balances, so the caller supplies what has already ")
	b.WriteString("been claimed:\n\n")
	b.WriteString("| at month | already claimed | claimable |\n|---|---|---|\n")
	for _, c := range [][2]int64{{6, 0}, {6, 300}, {6, 600}, {12, 600}} {
		b.WriteString("| " + strconv.FormatInt(c[0], 10) + " | " +
			strconv.FormatInt(c[1], 10) + " | " +
			strconv.FormatInt(s.Claimable(c[0], c[1]), 10) + " |\n")
	}

	b.WriteString("\n## Integer rounding\n\n")
	b.WriteString("All arithmetic is integer, no float ever reaches consensus state. ")
	b.WriteString("Rounding is **down**, so nobody is ever paid more than they earned, ")
	b.WriteString("and the final instalment collects the remainder.\n\n")
	odd, _ := cliffvesting.NewLinear(1000, 0, 3)
	b.WriteString("`1000` over `3` periods:\n\n")
	b.WriteString("| t | vested |\n|---|---|\n")
	for m := int64(0); m <= 3; m++ {
		b.WriteString("| " + strconv.FormatInt(m, 10) + " | " +
			strconv.FormatInt(odd.Vested(m), 10) + " |\n")
	}
	b.WriteString("\n`333 + 333 + 334`, and the end is exactly `1000`, never `999`.\n\n")

	b.WriteString("## Bug 1: a rate truncated to zero\n\n")
	tiny, _ := cliffvesting.NewLinear(7, 0, 1000)
	b.WriteString("When the total is smaller than the duration, computing a per-tick rate ")
	b.WriteString("first truncates it to zero and **nothing ever vests**. Multiplying ")
	b.WriteString("before dividing keeps it honest. `7` tokens over `1000` ticks:\n\n")
	b.WriteString("| t | vested |\n|---|---|\n")
	for _, m := range []int64{100, 150, 500, 1000} {
		b.WriteString("| " + strconv.FormatInt(m, 10) + " | " +
			strconv.FormatInt(tiny.Vested(m), 10) + " |\n")
	}

	b.WriteString("\n## Bug 2: a product that leaves int64\n\n")
	b.WriteString("Multiplying first is only safe if the product fits. Over a term ")
	b.WriteString("measured in **seconds**, `total * elapsed` passes 2^63 for any grant ")
	b.WriteString("above about `146,036` whole coins, and a wrapped int64 is still a ")
	b.WriteString("valid int64: `v0` of this library returned a **negative** vested ")
	b.WriteString("amount and nothing signalled it. `v1` routes the product through a ")
	b.WriteString("128-bit intermediate.\n\n")
	b.WriteString("A real two-year schedule, `1789225200` to `1852383600`, at the ")
	b.WriteString("halfway mark:\n\n")
	b.WriteString("| grant | vested at halfway | expected |\n|---|---|---|\n")
	const (
		vStart int64 = 1789225200
		vEnd   int64 = 1852383600
	)
	for _, total := range []int64{100000000000, 146037000000, 318720000000000} {
		big, err := cliffvesting.NewLinear(total, vStart, vEnd)
		if err != nil {
			continue
		}
		b.WriteString("| " + strconv.FormatInt(total, 10) + " | " +
			strconv.FormatInt(big.Vested(vStart+(vEnd-vStart)/2), 10) + " | " +
			strconv.FormatInt(total/2, 10) + " |\n")
	}
	return b.String()
}
