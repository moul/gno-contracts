// Package pullpaymentdemo is a small gnoweb demo of the escrow ledger provided
// by the [p/moul/x/daily/pullpayment](/p/moul/x/daily/pullpayment/v1) library:
// crediting a split, claiming it, and why a reentrant claim gets nothing.
//
// It contains no ledger logic of its own and holds no coins. Stateless, so
// Render is deterministic — which is precisely what the library is for.
package pullpaymentdemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/x/daily/pullpayment/v1"
)

// Render renders the demo for gnoweb.
func Render(path string) string {
	var b strings.Builder
	b.WriteString("# Pull Payment\n\n")
	b.WriteString("Credit and let recipients withdraw, demoing the ")
	b.WriteString("[`p/moul/x/daily/pullpayment`](/p/moul/x/daily/pullpayment/v1) library.\n\n")

	b.WriteString("## Why not just send?\n\n")
	b.WriteString("Pushing value hands control to the recipient in the middle of your ")
	b.WriteString("state transition, and a hostile recipient re-enters before you have ")
	b.WriteString("finished updating. Pulling inverts it: you record a debt, and the ")
	b.WriteString("recipient's own withdrawal is the only state being touched.\n\n")

	l := pullpayment.New()
	l.CreditMany([]string{"alice", "bob", "carol"}, []int64{500, 300, 200})

	b.WriteString("## A split, credited\n\n")
	b.WriteString(table(l))
	b.WriteString("\nThe holding realm must keep `")
	b.WriteString(strconv.FormatInt(l.TotalOwed(), 10))
	b.WriteString("` in reserve — that is what `TotalOwed` is for.\n\n")

	b.WriteString("## Bob claims\n\n")
	amt, _ := l.Withdraw("bob")
	b.WriteString("`Withdraw(\"bob\")` → `" + strconv.FormatInt(amt, 10) + "`, and the ledger ")
	b.WriteString("is updated **before** the caller transfers anything:\n\n")
	b.WriteString(table(l))
	b.WriteString("\nReserve is now `" + strconv.FormatInt(l.TotalOwed(), 10) + "`.\n\n")

	b.WriteString("## The reentrancy attempt\n\n")
	b.WriteString("Bob's handler calls straight back in, before the transfer completes:\n\n")
	again, err := l.Withdraw("bob")
	b.WriteString("- second `Withdraw(\"bob\")` → `" + strconv.FormatInt(again, 10) + "`, error: `")
	if err != nil {
		b.WriteString(err.Error())
	} else {
		b.WriteString("<nil>")
	}
	b.WriteString("`\n\n")
	b.WriteString("Nothing left to take. The balance was deleted before control left the ")
	b.WriteString("function — checks, effects, *then* interactions. Lifetime withdrawn is ")
	b.WriteString("still `" + strconv.FormatInt(l.TotalWithdrawn(), 10) + "`, not double.\n\n")

	b.WriteString("## Credits accumulate\n\n")
	l.Credit("alice", 100)
	b.WriteString("`Credit(\"alice\", 100)` on top of her existing balance:\n\n")
	b.WriteString(table(l))
	b.WriteString("\nOne withdrawal collects the lot — no dust left behind.\n\n")

	b.WriteString("## Batch credits are all-or-nothing\n\n")
	b.WriteString("A split that is partly invalid applies **none** of itself; a ledger ")
	b.WriteString("half-agreeing with the funds it guards is worse than a rejected call:\n\n")
	before := l.TotalOwed()
	batchErr := l.CreditMany([]string{"dave", "eve"}, []int64{10, -1})
	b.WriteString("- `CreditMany([dave, eve], [10, -1])` → `")
	if batchErr != nil {
		b.WriteString(batchErr.Error())
	}
	b.WriteString("`\n- total owed before: `" + strconv.FormatInt(before, 10) + "`, after: `")
	b.WriteString(strconv.FormatInt(l.TotalOwed(), 10) + "` — unchanged, and `dave` was not credited\n")
	return b.String()
}

func table(l *pullpayment.Ledger) string {
	var b strings.Builder
	b.WriteString("| payee | owed |\n|---|---|\n")
	l.Iterate(func(p string, amt int64) bool {
		b.WriteString("| `" + p + "` | " + strconv.FormatInt(amt, 10) + " |\n")
		return false
	})
	return b.String()
}
