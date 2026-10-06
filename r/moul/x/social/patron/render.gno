package patron

import (
	"strconv"
	"strings"

	"chain/runtime"

	"gno.land/p/moul/kit/num/v0"
	"gno.land/p/moul/kit/store/v0"
	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/realmpath/v0"
	"gno.land/p/moul/txlink/v0"
	pt "gno.land/p/moul/x/social/patron/v0"
)

// pageSize is how many plans the index lists at once.
const pageSize = 20

// titleWidth is how much of a plan's title a listing shows.
const titleWidth = 40

// Render routes two views: the index and one plan.
func Render(path string) string {
	req := realmpath.Parse(path)

	switch {
	case strings.HasPrefix(req.Path, "plan/"):
		return renderPlan(strings.TrimPrefix(req.Path, "plan/"))
	case req.Path == "":
		return renderIndex(req)
	default:
		return md.H1("Not found") + "No such view: " + ui.Inline(req.Path)
	}
}

func renderIndex(req *realmpath.Request) string {
	now := runtime.ChainHeight()

	out := md.H1("Patron")
	out += "Recurring support for a builder. A creator opens a plan with a price per " +
		"period and a period measured in blocks, and a supporter buys whole periods of " +
		"it with " + md.InlineCode("ugnot") + ".\n\n"
	out += md.Blockquote("There is no cron on chain, so a renewal is a pull and not a " +
		"push: nothing here can charge anybody. A supporter renews by paying again, and " +
		"renewing early never loses time already paid for.") + "\n"

	stats := ui.NewTable("plans", "owed to creators and supporters", "block")
	stats.Row(
		strconv.Itoa(plans.Count()),
		num.GNOTf(plans.TotalOwed()),
		strconv.FormatInt(now, 10),
	)
	out += stats.String()

	out += md.H2("Plans")
	out += planTable(plans.List(pageNum(req), pageSize), now)

	out += "\n" + ui.Action("➕ Open a plan", "Open",
		"title", "", "description", "", "pricePerPeriod", "", "periodBlocks", "") +
		" · " + ui.Action("💰 Withdraw what I am owed", "Withdraw") + "\n"

	out += md.H2("What it does not do")
	out += md.BulletList([]string{
		"**It does not charge anybody.** A renewal is a payment the supporter signs.",
		"**It does not stream.** A creator is credited the whole price at the moment " +
			"it is paid, so a supporter who stops being active is not refunded and no " +
			"part of a paid period comes back. Escrowed streaming needs a claim " +
			"schedule and a refund path, which is the v1.",
		"**It does not issue a token.** Minting a creator coin per period paid is " +
			"easy; the sink is not, because what it would be redeemed for is a promise " +
			"made off chain.",
	})

	return out
}

func renderPlan(raw string) string {
	id, ok := store.ParseID(raw)
	if !ok {
		return md.H1("Patron") + "Not a plan id: " + ui.Inline(raw)
	}
	p, found := plans.Get(id)
	if !found {
		return md.H1("Patron") + "No plan #" + id.String()
	}
	now := runtime.ChainHeight()

	out := md.H1("Plan #" + id.String() + ": " + ui.Inline(p.Title))
	if p.Description != "" {
		out += md.Blockquote(ui.Inline(p.Description)) + "\n"
	}

	status := "open"
	if !p.Open {
		status = "closed to new subscriptions"
	}
	facts := ui.NewTable("creator", "price per period", "period", "status")
	facts.Row(
		ui.Addr(p.Creator),
		num.GNOTf(p.PricePerPeriod),
		strconv.FormatInt(p.PeriodBlocks, 10)+" blocks",
		status,
	)
	out += facts.String()

	if p.Open {
		// The link carries the send amount, so the price is not something a
		// supporter has to copy out of the table and retype.
		out += md.Link(
			"💜 Support for one period ("+num.GNOTf(p.PricePerPeriod)+")",
			txlink.Realm(realmPath).NewLink("Subscribe").
				AddArgs("planID", id.String()).
				SetSend(strconv.FormatInt(p.PricePerPeriod, 10)+denom).
				URL(),
		) + "\n\n"
		out += "Paying " + md.InlineCode("n") + " times the price buys " +
			md.InlineCode("n") + " periods at once. Anything left over under one " +
			"period is credited back to you, not kept: take it with " +
			md.InlineCode("Withdraw") + ".\n"
	} else {
		out += ui.Empty("This plan takes no new subscriptions. Anything already paid " +
			"for runs to its own block.")
	}

	out += md.H2("Supporters")
	out += supporterTable(p, now)

	out += md.H2("Creator")
	out += "Earned across every plan: " + md.Bold(num.GNOTf(plans.EarnedBy(p.Creator))) +
		" · withdrawable now: " + md.Bold(num.GNOTf(plans.CreditOf(p.Creator))) + "\n\n"
	out += ui.Action("🚪 Close", "Close", "planID", id.String()) +
		" · " + ui.Action("🔓 Reopen", "Reopen", "planID", id.String()) +
		" · " + ui.Action("💰 Withdraw", "Withdraw") + "\n\n"
	out += md.Link("← every plan", pt.RealmURL(realmPath)) + "\n"

	return out
}

// planTable lists plans.
//
// The link text is the plan NUMBER and not its title, which is the one thing
// to copy from here. md.Link escapes its text with the inline escaper, and the
// inline escaper does not touch a pipe, because a pipe means nothing in a
// sentence: a user title carried inside a link inside a table cell therefore
// still opens a column. So the title gets its own cell and goes through
// ui.Cell, which is the escaper that knows it is in a table. It is truncated
// first with ui.ShortN, which does not escape, so the cut can never strand a
// backslash that the escaper had just inserted.
func planTable(items []pt.Listing, now int64) string {
	t := ui.NewTable("#", "plan", "creator", "per period", "period", "supporters", "")
	for _, it := range items {
		mark := "🟢"
		if !it.Plan.Open {
			mark = "🔒"
		}
		t.Row(
			md.Link(it.ID.String(), pt.PlanURL(realmPath, it.ID)),
			ui.Cell(ui.ShortN(it.Plan.Title, titleWidth, 0)),
			ui.Addr(it.Plan.Creator),
			num.GNOTf(it.Plan.PricePerPeriod),
			strconv.FormatInt(it.Plan.PeriodBlocks, 10)+" blocks",
			strconv.Itoa(it.Plan.ActiveCount(now))+" of "+strconv.Itoa(it.Plan.SupporterCount()),
			mark,
		)
	}
	return t.OrEmpty("No plans yet.")
}

func supporterTable(p *pt.Plan, now int64) string {
	t := ui.NewTable("supporter", "paid through block", "active")
	for _, who := range p.Supporters() {
		active := "no"
		if p.IsActive(who, now) {
			active = "yes"
		}
		t.Row(ui.Addr(who), strconv.FormatInt(p.PaidThrough(who), 10), active)
	}
	return t.OrEmpty("Nobody supports this plan yet.")
}

// pageNum reads ?page= and falls back to the first page for anything it
// cannot read, which is the only answer a Render can give: there is nobody to
// report an error to.
func pageNum(req *realmpath.Request) int {
	n, err := strconv.Atoi(req.Query.Get("page"))
	if err != nil || n < 1 {
		return 1
	}
	return n
}
