// Package crondemo is a small gnoweb demo of the cron expression parser
// provided by the [p/moul/x/daily/cron](/p/moul/x/daily/cron/v0) library: the
// grammar, the next firing times of a handful of schedules, the union rule
// that governs the two day fields, and the expression that never fires.
//
// It contains no scheduling logic of its own, and no state. Every instant on
// the page is computed from the fixed anchor below rather than from
// time.Now(), which is what lets an example test pin the output: a block
// timestamp would make the page different on every call and identical to
// nothing.
package crondemo

import (
	"strconv"
	"strings"
	"time"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/x/daily/cron/v0"
)

// anchor is the instant every "next" on this page is measured from: a Tuesday
// morning, deliberately mid-minute so the exclusive boundary is visible.
var anchor = time.Date(2026, time.March, 10, 9, 17, 0, 0, time.UTC)

// schedules is the worked example: one line per shape of the grammar.
var schedules = []struct {
	expr string
	what string
}{
	{"* * * * *", "every minute"},
	{"*/15 * * * *", "every quarter hour"},
	{"0 * * * *", "on the hour"},
	{"5,25,45 * * * *", "a list of minutes"},
	{"5/20 * * * *", "from minute 5, every 20"},
	{"30 8 * * 1-5", "weekday mornings"},
	{"0 12 * * sat,sun", "weekend noon"},
	{"0 0 1 jan,jul *", "twice a year"},
	{"0 0 29 2 *", "the leap day"},
}

// macros is the @shorthand table, each paired with what it expands to.
var macros = []struct {
	macro string
	same  string
}{
	{"@hourly", "0 * * * *"},
	{"@daily", "0 0 * * *"},
	{"@weekly", "0 0 * * 0"},
	{"@monthly", "0 0 1 * *"},
	{"@yearly", "0 0 1 1 *"},
}

// Render renders the demo for gnoweb.
//
//	Render("") / Render("/") -> the full demo
func Render(path string) string {
	var b strings.Builder

	b.WriteString("# Cron expressions\n\n")
	b.WriteString("The five-field crontab grammar, parsed and answered: given a ")
	b.WriteString("schedule and an instant, when does it next fire. Demoing the ")
	b.WriteString("[`p/moul/x/daily/cron`](/p/moul/x/daily/cron/v0) library.\n\n")

	b.WriteString("## The grammar\n\n")
	gt := ui.NewTable("position", "field", "range", "names")
	gt.Row("1", "minute", "`0-59`", "")
	gt.Row("2", "hour", "`0-23`", "")
	gt.Row("3", "day of month", "`1-31`", "")
	gt.Row("4", "month", "`1-12`", "`jan`..`dec`")
	gt.Row("5", "day of week", "`0-7`", "`sun`..`sat`")
	b.WriteString(gt.String() + "\n")
	b.WriteString("Every field is a comma-separated list whose items are a value, ")
	b.WriteString("a range, a star, or any of those with a step: `5`, `5-30`, ")
	b.WriteString("`*`, `*/15`, `5-30/5`, `5/20`. In the weekday field `0` and ")
	b.WriteString("`7` are both Sunday, which is what keeps `5-7` meaning Friday ")
	b.WriteString("through Sunday instead of running backwards.\n\n")

	b.WriteString("## Next firing times\n\n")
	b.WriteString("Measured from `" + stamp(anchor) + "`, and strictly after it: ")
	b.WriteString("a schedule handed its own firing time answers with the ")
	b.WriteString("following one.\n\n")
	st := ui.NewTable("expression", "meaning", "next", "then", "and then")
	for _, sc := range schedules {
		s, err := cron.Parse(sc.expr)
		if err != nil {
			st.Row(ui.Cell(sc.expr), ui.Cell(sc.what), ui.Cell(err.Error()), "", "")
			continue
		}
		cells := []string{"never", "", ""}
		for i, t := range s.NextN(anchor, 3) {
			cells[i] = stamp(t)
		}
		st.Row("`"+sc.expr+"`", sc.what, cells[0], cells[1], cells[2])
	}
	b.WriteString(st.String() + "\n")
	b.WriteString("The last row is not a failure. `0 0 29 2 *` is a perfectly ")
	b.WriteString("well formed expression that skips three years out of four, ")
	b.WriteString("and the parser has no business rejecting it.\n\n")

	b.WriteString("## The two day fields are a union\n\n")
	b.WriteString("This is the rule a reimplementation gets wrong. When **both** ")
	b.WriteString("the day-of-month and the day-of-week field are narrowed, a ")
	b.WriteString("day matches when **either** does. `0 0 13 * 5` is the ")
	b.WriteString("classic: the 13th of the month OR any Friday, never the ")
	b.WriteString("intersection, which is why it also fires on ordinary ")
	b.WriteString("Fridays.\n\n")
	ut := ui.NewTable("expression", "day of month", "day of week", "combined", "next three")
	for _, c := range []struct {
		expr string
		dom  string
		dow  string
		rule string
	}{
		{"0 0 13 * 5", "the 13th", "Friday", "**either**"},
		{"0 0 13 * *", "the 13th", "any", "the 13th"},
		{"0 0 * * 5", "any", "Friday", "Friday"},
	} {
		s := cron.MustParse(c.expr)
		days := make([]string, 0, 3)
		for _, t := range s.NextN(anchor, 3) {
			days = append(days, stamp(t))
		}
		ut.Row("`"+c.expr+"`", c.dom, c.dow, c.rule, strings.Join(days, ", "))
	}
	b.WriteString(ut.String() + "\n")
	b.WriteString("When only one of the two is narrowed the other matches every ")
	b.WriteString("day, so the union and the intersection agree and there is ")
	b.WriteString("nothing to decide. The rule only bites on the first row.\n\n")

	b.WriteString("## Macros\n\n")
	mt := ui.NewTable("macro", "expands to", "next")
	for _, m := range macros {
		s := cron.MustParse(m.macro)
		next, ok := s.Next(anchor)
		when := "never"
		if ok {
			when = stamp(next)
		}
		mt.Row("`"+m.macro+"`", "`"+m.same+"`", when)
	}
	b.WriteString(mt.String() + "\n")
	b.WriteString("`@annually` is `@yearly` and `@midnight` is `@daily`. A ")
	b.WriteString("schedule reports the expression it was parsed from, so a ")
	b.WriteString("macro stays a macro on the way back out.\n\n")

	b.WriteString("## What a bad expression says\n\n")
	et := ui.NewTable("expression", "error")
	for _, bad := range []string{
		"* * * *",
		"60 * * * *",
		"* * * * 8",
		"* * * * 5-1",
		"*/0 * * * *",
		"@fortnightly",
	} {
		_, err := cron.Parse(bad)
		msg := "accepted"
		if err != nil {
			msg = err.Error()
		}
		et.Row("`"+bad+"`", ui.Cell(msg))
	}
	b.WriteString(et.String() + "\n")
	b.WriteString("The field is named in the message. Five fields all accept ")
	b.WriteString("numbers, so `out of range` on its own says nothing about ")
	b.WriteString("which one to go and fix.\n\n")

	b.WriteString("## Why a realm would want this\n\n")
	b.WriteString("A chain has no timer. Nothing on gno.land wakes a realm up, ")
	b.WriteString("so a schedule is not a thing that runs: it is a thing that ")
	b.WriteString("is *checked*. A realm stores the expression, and whoever ")
	b.WriteString("calls in next asks whether the due instant has passed. ")
	b.WriteString("`Next` turns a crontab line into that one comparison, and ")
	b.WriteString("`Matches` answers it for the current block without any ")
	b.WriteString("arithmetic at the call site.\n\n")
	b.WriteString("Everything here is UTC on purpose. A block timestamp carries ")
	b.WriteString("no local zone, and a schedule whose answer depended on one ")
	b.WriteString("would not be the same schedule on every validating node.\n")

	return b.String()
}

// stamp formats an instant as the page shows it: date, minute, weekday.
//
// Written out with strconv rather than reached for from a formatter because
// ufmt/v0 has no width flags, and a zero-padded minute is the whole point.
func stamp(t time.Time) string {
	return strconv.Itoa(t.Year()) + "-" + pad2(int(t.Month())) + "-" + pad2(t.Day()) +
		" " + pad2(t.Hour()) + ":" + pad2(t.Minute()) +
		" " + weekdayName(t.Weekday())
}

// pad2 renders 0..99 with a leading zero.
func pad2(v int) string {
	if v < 10 {
		return "0" + strconv.Itoa(v)
	}
	return strconv.Itoa(v)
}

// weekdayName is the three-letter form, spelled the way the grammar spells it.
func weekdayName(d time.Weekday) string {
	names := []string{"sun", "mon", "tue", "wed", "thu", "fri", "sat"}
	return names[int(d)]
}
