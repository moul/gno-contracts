package vesting

import (
	"strconv"
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/realmpath/v0"
	"gno.land/p/moul/vesting/v0"
)

// Render serves three shapes:
//
//	/r/moul/vesting/v0                     the seeded schedules
//	/r/moul/vesting/v0:g1...               one address, its declared schedule
//	/r/moul/vesting/v0:g1...?o=&s=&e=&d=   one address, a schedule you supply
//
// The query form stores nothing. It exists so an address that has not declared
// anything can still get a real answer: paste the schedule out of
// `gnokey query auth/accounts/<addr>` and the balance is still read from chain.
func Render(path string) string {
	req := realmpath.Parse(path)
	target := strings.TrimSpace(req.PathPart(0))

	if target == "" {
		return renderIndex()
	}
	if !isAddr(target) {
		return header() + ui.Empty("`"+ui.Inline(target)+"` is not a gno.land address.") +
			"\n" + lookupForm()
	}
	addr := address(target)

	// An ad-hoc schedule in the query beats a declared one, and is labelled as
	// coming from the caller.
	if raw := req.Query.Get("o"); raw != "" {
		sch, err := scheduleFromQuery(req)
		if err != "" {
			return header() + ui.Empty(err) + "\n" + lookupForm()
		}
		return header() + renderAccount(addr, sch, sourceQuery, "") + "\n" + lookupForm()
	}

	if e, ok := lookup(addr); ok {
		src := sourceDeclared
		if e.seeded {
			src = sourceSeeded
		}
		return header() + renderAccount(addr, e.schedule, src, e.label) + "\n" + lookupForm()
	}
	return header() + renderUnknown(addr) + "\n" + lookupForm()
}

// Where a schedule came from. This is the distinction the whole page turns on,
// so it is a value and not a boolean buried in a branch.
type source int

const (
	sourceSeeded   source = iota // a source constant in this realm
	sourceDeclared               // written by the address itself
	sourceQuery                  // typed into the URL by whoever is looking
	sourceNone                   // there is none
)

func (s source) label() string {
	switch s {
	case sourceSeeded:
		return "seeded in this realm's source"
	case sourceDeclared:
		return "declared by the address itself"
	case sourceQuery:
		return "supplied in the URL by you"
	}
	return "unknown"
}

func header() string {
	return "# Vesting\n\n" +
		"How much of an account's balance can actually move right now.\n\n"
}

func renderIndex() string {
	var b strings.Builder
	b.WriteString(header())

	t := ui.NewTable("account", "balance", "spendable", "locked", "vested")
	declared.Iterate("", "", func(key string, v any) bool {
		e := v.(*entry)
		addr := address(key)
		bal := balanceOf(addr)
		n := now()
		name := ui.AddrText(addr)
		if e.label != "" {
			name = ui.Inline(e.label) + " " + ui.Addr(addr)
		}
		t.Row(
			name,
			gnot(bal),
			gnot(e.schedule.Spendable(bal, n)),
			gnot(lockedCapped(e.schedule, bal, n)),
			permille(e.schedule.PermilleVested(n)),
		)
		return false
	})
	b.WriteString(t.OrEmpty("No schedules yet."))

	b.WriteString("\n")
	b.WriteString(lookupForm())
	b.WriteString("\n## What is real here, and what is not\n\n")
	b.WriteString("| figure | where it comes from |\n|---|---|\n")
	b.WriteString("| balance | read from the chain every render, `banker.GetCoins` |\n")
	b.WriteString("| the clock | read from the chain every render, the block time |\n")
	b.WriteString("| the schedule | **supplied**, because no realm can read one |\n\n")
	b.WriteString("A realm's whole view of an account is its TOTAL balance, locked coins ")
	b.WriteString("included. `std.VestingSchedule` lives in the auth store and no native ")
	b.WriteString("reaches it, so the curve has to be told to this realm rather than found.\n\n")
	b.WriteString("That is safe to cache because a schedule can never change: it is set ")
	b.WriteString("once, at genesis, and no message type creates or modifies one. A ")
	b.WriteString("schedule declared correctly today is correct forever.\n")
	return b.String()
}

func renderAccount(addr address, s vesting.Schedule, src source, label string) string {
	var b strings.Builder
	n := now()
	bal := balanceOf(addr)

	b.WriteString("## ")
	if label != "" {
		b.WriteString(ui.Inline(label))
		b.WriteString(" ")
	}
	b.WriteString(ui.AddrText(addr))
	b.WriteString("\n\n")

	if s.IsZero() {
		b.WriteString("No vesting schedule, so the whole balance moves.\n\n")
		b.WriteString("| | |\n|---|---|\n")
		b.WriteString("| balance | **" + gnot(bal) + "** |\n")
		b.WriteString("| spendable | **" + gnot(bal) + "** |\n\n")
		b.WriteString(sourceNote(src))
		return b.String()
	}

	locked := lockedCapped(s, bal, n)
	t := ui.NewTable("", "")
	t.Row("balance", "**"+gnot(bal)+"**")
	t.Row("spendable now", "**"+gnot(s.Spendable(bal, n))+"**")
	t.Row("locked now", gnot(locked))
	t.Row("granted", gnot(s.Original))
	t.Row("vested", gnot(s.Vested(n))+" ("+permille(s.PermilleVested(n))+")")
	t.Row("still to vest", gnot(s.Locked(n)))
	t.Row("curve", s.Type.String())
	t.Row("term", tstamp(s.Start)+" to "+tstamp(s.End))
	t.Row("finishes in", duration(s.RemainingSeconds(n)))
	b.WriteString(t.String())
	b.WriteString("\n")

	if s.Locked(n) > bal {
		b.WriteString("\n> This account holds less than its schedule still locks, so ")
		b.WriteString("nothing moves at all. That happens when coins were spent while ")
		b.WriteString("they were free and the grant has since outrun the balance.\n")
	}

	b.WriteString("\n")
	b.WriteString(sourceNote(src))
	return b.String()
}

func renderUnknown(addr address) string {
	var b strings.Builder
	bal := balanceOf(addr)
	b.WriteString("## ")
	b.WriteString(ui.AddrText(addr))
	b.WriteString("\n\nNo schedule on file for this address.\n\n")
	b.WriteString("| | |\n|---|---|\n")
	b.WriteString("| balance | **" + gnot(bal) + "** |\n")
	b.WriteString("| spendable | unknown |\n\n")
	b.WriteString("The balance above is real. How much of it moves is not knowable from ")
	b.WriteString("inside a realm. Read the schedule off the chain:\n\n")
	b.WriteString("```\ngnokey query auth/accounts/" + addr.String() +
		" -remote https://rpc.gno.land:443\n```\n\n")
	b.WriteString("then either append it to this URL as `?o=<original_vesting>&s=<start_time>")
	b.WriteString("&e=<end_time>` (add `&d=1` for a `delayed` schedule), or, if this address ")
	b.WriteString("is yours, put it on file so the link works for everyone:\n\n")
	b.WriteString(ui.Action("Declare this schedule", "Declare",
		"original", "", "start", "", "end", "", "delayed", "false"))
	b.WriteString("\n")
	return b.String()
}

func sourceNote(src source) string {
	s := "Balance and clock are read from the chain. The schedule is " + src.label() + "."
	if src == sourceQuery {
		s += " Nothing was stored."
	}
	if src == sourceDeclared {
		s += " Only that address can write or remove it, so it can misdescribe nobody else."
	}
	return "> " + s + "\n"
}

func lookupForm() string {
	return "## Check another address\n\n" +
		"Append it to the path: `" + Link + ":g1…`\n\n" +
		"| | |\n|---|---|\n" +
		"| put your own schedule on file | " +
		ui.Action("Declare", "Declare", "original", "", "start", "", "end", "", "delayed", "false") +
		" |\n| take it off again | " + ui.Action("Forget", "Forget") + " |\n"
}

// scheduleFromQuery reads a one-off schedule out of the URL. It returns a
// human-readable reason rather than an error value, because every caller turns
// it straight into page text.
func scheduleFromQuery(req *realmpath.Request) (vesting.Schedule, string) {
	o, err := strconv.ParseInt(req.Query.Get("o"), 10, 64)
	if err != nil {
		return vesting.Schedule{}, "`o` (the original vesting amount, in ugnot) is not a number."
	}
	s, err := strconv.ParseInt(orZero(req.Query.Get("s")), 10, 64)
	if err != nil {
		return vesting.Schedule{}, "`s` (the start time, unix seconds) is not a number."
	}
	e, err := strconv.ParseInt(orZero(req.Query.Get("e")), 10, 64)
	if err != nil {
		return vesting.Schedule{}, "`e` (the end time, unix seconds) is not a number."
	}
	typ := vesting.Continuous
	if d := req.Query.Get("d"); d == "1" || d == "true" {
		typ = vesting.Delayed
	}
	sch, verr := vesting.New(o, s, e, typ)
	if verr != nil {
		return vesting.Schedule{}, "That is not a valid schedule: " + verr.Error() + "."
	}
	return sch, ""
}

func orZero(s string) string {
	if s == "" {
		return "0"
	}
	return s
}

// lockedCapped is what the account cannot move, which is never more than it
// holds. The schedule alone can say otherwise once coins have been spent.
func lockedCapped(s vesting.Schedule, balance, n int64) int64 {
	l := s.Locked(n)
	if l > balance {
		return balance
	}
	if l < 0 {
		return 0
	}
	return l
}

// tstamp renders a unix second as a plain UTC date, which is all a two-year
// term needs. gno has no time formatting worth the dependency here.
func tstamp(sec int64) string {
	y, m, d := civil(sec / 86400)
	return ufmtDate(y, m, d)
}

// civil converts a day count since 1970-01-01 to a calendar date, by Howard
// Hinnant's civil_from_days. Integer only, no time package, no locale.
func civil(z int64) (year int64, month int64, day int64) {
	z += 719468
	era := z / 146097
	if z < 0 {
		era = (z - 146096) / 146097
	}
	doe := z - era*146097
	yoe := (doe - doe/1460 + doe/36524 - doe/146096) / 365
	y := yoe + era*400
	doy := doe - (365*yoe + yoe/4 - yoe/100)
	mp := (5*doy + 2) / 153
	d := doy - (153*mp+2)/5 + 1
	m := mp + 3
	if mp >= 10 {
		m = mp - 9
	}
	if m <= 2 {
		y++
	}
	return y, m, d
}

func ufmtDate(y, m, d int64) string {
	return strconv.FormatInt(y, 10) + "-" + pad2(m) + "-" + pad2(d)
}

func pad2(n int64) string {
	s := strconv.FormatInt(n, 10)
	if len(s) < 2 {
		return "0" + s
	}
	return s
}
