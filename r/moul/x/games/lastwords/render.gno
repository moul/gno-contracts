package lastwords

import (
	"strconv"
	"strings"

	"chain/runtime"

	"gno.land/p/moul/kit/ui/v0"
)

// Render shows the slot, the clock and the money. The message is caller-typed
// text, so it goes through ui.Inline: a stored string that renders as markdown
// is a phishing link on a page nobody can edit, and this realm's whole product
// is a string somebody else wrote.
func Render(path string) string {
	h := runtime.ChainHeight()
	var b strings.Builder

	b.WriteString("# Last Words\n\n")

	if message == "" {
		b.WriteString("_The slot is empty. Whoever writes last, writes forever._\n\n")
	} else {
		b.WriteString("> " + ui.Inline(message) + "\n\n")
		b.WriteString("by " + ui.AddrOf(author.String()) + ", for " + gnot(paid) + " GNOT\n\n")
	}

	closed := clk.Expired(h)
	b.WriteString("## The clock\n\n")
	if closed {
		b.WriteString("**Closed** at height " + strconv.FormatInt(clk.Deadline(), 10) + ". ")
		if settled {
			b.WriteString("Settled: the pot has been credited, call `Withdraw` to sweep yours.\n\n")
		} else {
			b.WriteString("Anyone may call `Settle` to split the pot.\n\n")
		}
	} else {
		b.WriteString("Open for another **" + strconv.FormatInt(clk.Remaining(h), 10) +
			"** blocks, until height " + strconv.FormatInt(clk.Deadline(), 10) + ".\n\n")
		if clk.Final() {
			b.WriteString("This is the **last stretch**: the deadline has reached the hard end at " +
				strconv.FormatInt(clk.HardEnd(), 10) + " and no write can move it again.\n\n")
		} else {
			b.WriteString("Hard end at height " + strconv.FormatInt(clk.HardEnd(), 10) +
				". A write buys " + strconv.FormatInt(BumpPct, 10) +
				"% of the gap to it, never less than " + strconv.FormatInt(Floor, 10) + " blocks.\n\n")
		}
	}

	b.WriteString("## The money\n\n")
	b.WriteString("| | |\n|---|---|\n")
	b.WriteString("| Pot | " + gnot(pot) + " GNOT |\n")
	b.WriteString("| Price of the next write | " + gnot(Price("")) + " GNOT, plus " +
		strconv.FormatInt(PerByte, 10) + " ugnot per byte |\n")
	b.WriteString("| Writes | " + strconv.FormatInt(writes, 10) + " |\n")
	b.WriteString("| Writers | " + strconv.Itoa(len(order)) + " |\n")
	b.WriteString("| Owed, unswept | " + gnot(ledger.TotalOwed()) + " GNOT |\n\n")

	b.WriteString("The holder does **not** take the pot. It goes to everyone else who wrote, ")
	b.WriteString("pro rata to what they paid. Half of every payment is credited to the writer ")
	b.WriteString("it displaced, immediately.\n\n")

	if !ledger.IsEmpty() {
		b.WriteString("## Owed\n\n| address | ugnot |\n|---|---|\n")
		shown := 0
		ledger.Iterate(func(payee string, amount int64) bool {
			b.WriteString("| " + ui.AddrOf(payee) + " | " + strconv.FormatInt(amount, 10) + " |\n")
			shown++
			return shown >= 20
		})
		b.WriteString("\nCall `Withdraw` to sweep yours.\n")
	}

	return b.String()
}
