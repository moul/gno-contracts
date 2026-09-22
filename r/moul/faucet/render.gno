package faucet

import (
	"strconv"
	"strings"

	"gno.land/p/nt/markdown/sanitize/v0"
)

// Render shows the float, the open asks and everything already decided.
//
// Two paths: "" is the whole board, "req/<id>" is one request.
//
// Every string on this page that a caller typed goes through sanitize before
// it is concatenated. A reason is arbitrary text from an arbitrary account and
// Render output is markdown that gnoweb parses, so an unescaped one can plant
// a link, an image beacon or gnoweb chrome on a page the realm is signing for.
// This realm's path is permanent, so that bug could only ever be fixed at a
// new path.
func Render(path string) string {
	path = strings.TrimPrefix(path, "/")
	if id, ok := reqPath(path); ok {
		return renderOne(id)
	}
	return renderBoard()
}

func renderBoard() string {
	var b strings.Builder

	b.WriteString("# GNOT faucet\n\n")
	b.WriteString(intro)
	b.WriteString("\n\n")

	b.WriteString("| | |\n| --- | ---: |\n")
	b.WriteString("| Float available | **" + gnot(Balance()) + " GNOT** |\n")
	b.WriteString("| Paid out | " + gnot(totalSent) + " GNOT over " +
		strconv.FormatInt(sentCount, 10) + " request(s) |\n")
	b.WriteString("| Open requests | " + strconv.FormatInt(pendingN, 10) + " |\n")
	b.WriteString("| Refused | " + strconv.FormatInt(deniedCount, 10) + " |\n")
	b.WriteString("| Cap per request | " + gnot(maxPerRequest) + " GNOT |\n")
	b.WriteString("| Float address | `" + Address().String() + "` |\n\n")

	b.WriteString("## Open\n\n")
	b.WriteString(table(StatusPending))
	b.WriteString("\n## Decided\n\n")
	b.WriteString(table(""))

	b.WriteString("\n## Approvers\n\n")
	approvers.Iterate("", "", func(k string, _ any) bool {
		b.WriteString("- `" + k + "`\n")
		return false
	})

	b.WriteString("\n" + howto + "\n")
	return b.String()
}

// table lists requests in filing order, keeping only those in `want`, or
// everything already decided when want is empty.
func table(want string) string {
	var rows strings.Builder
	n := 0
	requests.Iterate("", "", func(_ string, v any) bool {
		r := v.(*request)
		if want == "" && r.Status == StatusPending {
			return false
		}
		if want != "" && r.Status != want {
			return false
		}
		n++
		rows.WriteString("| [" + strconv.FormatInt(r.ID, 10) + "](" + Link + ":req/" +
			strconv.FormatInt(r.ID, 10) + ") | `" + r.To.String() + "` | " +
			gnot(r.Amount) + " | " + sanitize.TableCell(excerpt(r.Reason, 60)) + " | " +
			r.Status + " |\n")
		return false
	})
	if n == 0 {
		return "_Nothing here yet._\n"
	}
	return "| # | To | GNOT | Why | State |\n| ---: | --- | ---: | --- | --- |\n" + rows.String()
}

func renderOne(id int64) string {
	r := find(id)
	if r == nil {
		return "# Request " + strconv.FormatInt(id, 10) + "\n\n_No such request._\n"
	}
	var b strings.Builder
	b.WriteString("# Request " + strconv.FormatInt(r.ID, 10) + "\n\n")
	b.WriteString("| | |\n| --- | --- |\n")
	b.WriteString("| To | `" + r.To.String() + "` |\n")
	b.WriteString("| Amount | " + gnot(r.Amount) + " GNOT |\n")
	b.WriteString("| Filed by | `" + r.By.String() + "` |\n")
	b.WriteString("| Filed at height | " + strconv.FormatInt(r.Asked, 10) + " |\n")
	b.WriteString("| State | " + r.Status + " |\n")
	if r.Status != StatusPending {
		b.WriteString("| Decided by | `" + r.Judge.String() + "` |\n")
		b.WriteString("| Decided at height | " + strconv.FormatInt(r.Decided, 10) + " |\n")
	}
	b.WriteString("\n**Why:** " + sanitize.InlineText(r.Reason) + "\n")
	if r.Note != "" {
		b.WriteString("\n**Refused because:** " + sanitize.InlineText(r.Note) + "\n")
	}
	b.WriteString("\n[Back to the faucet](" + Link + ")\n")
	return b.String()
}

// reqPath parses "req/<id>".
func reqPath(path string) (int64, bool) {
	rest, ok := strings.CutPrefix(path, "req/")
	if !ok {
		return 0, false
	}
	id, err := strconv.ParseInt(rest, 10, 64)
	if err != nil || id <= 0 {
		return 0, false
	}
	return id, true
}

// excerpt cuts to width RUNES, never bytes: slicing a multi-byte character in
// half puts invalid UTF-8 on the page, and one emoji in a reason is enough.
// It cuts before escaping, because escaping inserts backslashes and cutting an
// already-escaped string can strand a lone one that escapes the chrome after
// it.
func excerpt(s string, width int) string {
	r := []rune(s)
	if len(r) <= width+1 {
		return s
	}
	return string(r[:width]) + "…"
}

// gnot renders ugnot as GNOT with the trailing zeros of the fraction trimmed,
// so 100000000 reads as 100 and 1500000 as 1.5.
func gnot(ugnot int64) string {
	neg := ""
	if ugnot < 0 {
		neg, ugnot = "-", -ugnot
	}
	whole := strconv.FormatInt(ugnot/1_000_000, 10)
	frac := strconv.FormatInt(ugnot%1_000_000, 10)
	if frac == "0" {
		return neg + whole
	}
	for len(frac) < 6 {
		frac = "0" + frac
	}
	return neg + whole + "." + strings.TrimRight(frac, "0")
}

const (
	intro = "Somebody you trust has no GNOT and cannot use the public faucet. File a\n" +
		"request on their behalf, an approver releases it, and both halves stay on\n" +
		"this page with a reason attached. The faucet only ever spends what has been\n" +
		"sent to its own address."

	howto = "## How\n\n" +
		"`Request(to, amount, reason)` is open to anyone and moves no money.\n" +
		"`Approve(id, to, amount)` pays it, and only an approver can call it.\n\n" +
		"Send both in **one transaction**: a tm2 transaction stops at the first\n" +
		"message that fails and writes none of their state, so the ask and its\n" +
		"answer land together or not at all. Read `NextID` to address the approval,\n" +
		"and pass the recipient and the amount into it as well: if another request\n" +
		"takes that id first, the mismatch fails the transaction instead of paying\n" +
		"the wrong account."
)
