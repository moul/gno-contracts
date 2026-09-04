// Package cliffvestingdemo is a small gnoweb demo of the vesting calculator
// provided by the [p/moul/x/daily/cliffvesting](/p/moul/x/daily/cliffvesting/v1)
// library: the cliff step, the linear ramp, and integer rounding.
//
// It contains no vesting logic of its own and holds no coins. Stateless, so
// Render is deterministic — which is precisely what the library is for.
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
	b.WriteString("The library tracks no balances — the caller supplies what has already ")
	b.WriteString("been claimed:\n\n")
	b.WriteString("| at month | already claimed | claimable |\n|---|---|---|\n")
	for _, c := range [][2]int64{{6, 0}, {6, 300}, {6, 600}, {12, 600}} {
		b.WriteString("| " + strconv.FormatInt(c[0], 10) + " | " +
			strconv.FormatInt(c[1], 10) + " | " +
			strconv.FormatInt(s.Claimable(c[0], c[1]), 10) + " |\n")
	}

	b.WriteString("\n## Integer rounding\n\n")
	b.WriteString("All arithmetic is integer — no float ever reaches consensus state. ")
	b.WriteString("Rounding is **down**, so nobody is ever paid more than they earned, ")
	b.WriteString("and the final instalment collects the remainder.\n\n")
	odd, _ := cliffvesting.NewLinear(1000, 0, 3)
	b.WriteString("`1000` over `3` periods:\n\n")
	b.WriteString("| t | vested |\n|---|---|\n")
	for m := int64(0); m <= 3; m++ {
		b.WriteString("| " + strconv.FormatInt(m, 10) + " | " +
			strconv.FormatInt(odd.Vested(m), 10) + " |\n")
	}
	b.WriteString("\n`333 + 333 + 334` — the end is exactly `1000`, never `999`.\n\n")

	b.WriteString("## The bug this avoids\n\n")
	tiny, _ := cliffvesting.NewLinear(7, 0, 1000)
	b.WriteString("When the total is smaller than the duration, computing a per-tick rate ")
	b.WriteString("first truncates it to zero and **nothing ever vests**. Multiplying ")
	b.WriteString("before dividing keeps it honest — `7` tokens over `1000` ticks:\n\n")
	b.WriteString("| t | vested |\n|---|---|\n")
	for _, m := range []int64{100, 150, 500, 1000} {
		b.WriteString("| " + strconv.FormatInt(m, 10) + " | " +
			strconv.FormatInt(tiny.Vested(m), 10) + " |\n")
	}
	return b.String()
}
