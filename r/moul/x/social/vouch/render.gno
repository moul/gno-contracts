package vouch

import (
	"strconv"

	"gno.land/p/moul/kit/num/v0"
	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/realmpath/v0"
	vo "gno.land/p/moul/x/social/vouch/v0"
)

// Render routes two views: the realm's own index, and one address's page.
//
// An address carries no slash, so the per-address route is a path element and
// not a prefix strip.
func Render(path string) string {
	req := realmpath.Parse(path)

	switch req.PathPart(0) {
	case "":
		return renderIndex()
	case "addr":
		return renderAddr(req.PathPart(1))
	default:
		return md.H1("Not found") + "No such view: " + ui.Inline(req.Path)
	}
}

func renderIndex() string {
	out := md.H1("Vouch")
	out += "A web of trust other realms gate on. One address vouches for another, " +
		"in writing, optionally with GNOT locked behind it.\n\n"

	t := ui.NewTable("vouches", "people vouched for", "bonded", "awaiting withdrawal")
	t.Row(
		strconv.Itoa(graph.Count()),
		strconv.Itoa(graph.People()),
		num.GNOTf(graph.TotalBonded()),
		num.GNOTf(graph.TotalOwed()),
	)
	out += t.String()

	out += md.H2("Most vouched for")
	out += board()

	out += md.H2("The gate")
	out += "One line in the realm that wants it, and it costs no transaction:\n\n"
	out += md.LanguageCodeBlock("go", `import "`+realmPath+`"

if !vouch.IsTrusted(addr, 2) {
	panic("get two people to vouch for you first")
}`)
	out += md.Italic("A score counts distinct vouchers, so restating a vouch does not " +
		"raise it and revoking lowers it. It does not count distinct people: a pair " +
		"vouching for each other both reach one, which is why a real gate asks for " +
		"more.") + "\n\n"

	out += md.H2("Take part")
	out += ui.Action("\U0001F91D Vouch", "Vouch", "target", "", "reason", "") +
		" · " + ui.Action("\U0001F4B0 Withdraw a refunded bond", "Withdraw") + "\n\n"
	out += md.Italic("Coins sent with Vouch are locked as a bond on that vouch and come " +
		"back when you revoke it. There is no slashing: deciding that a vouch was a lie " +
		"needs an arbiter, and choosing one is the whole design question.") + "\n"

	return out
}

func board() string {
	rows := graph.Leaderboard(BoardSize)
	if len(rows) == 0 {
		return ui.Empty("Nobody has been vouched for yet.")
	}
	t := ui.NewTable("", "address", "vouchers", "bonded")
	for i, r := range rows {
		t.Row(
			ui.Podium(i),
			md.Link(ui.AddrText(r.Addr), vo.AddrURL(realmPath, r.Addr)),
			strconv.Itoa(r.Score),
			num.GNOTf(r.Bonded),
		)
	}
	return t.String()
}

func renderAddr(raw string) string {
	addr := address(raw)
	if !addr.IsValid() {
		return md.H1("Vouch") + "Not an address: " + ui.Inline(raw)
	}

	out := md.H1("Vouch for " + ui.AddrText(addr))
	out += ui.AddrFull(addr) + "\n\n"

	score := graph.ScoreOf(addr)
	t := ui.NewTable("vouchers", "bonded on them", "trusted at 2", "awaiting withdrawal")
	t.Row(
		strconv.Itoa(score),
		num.GNOTf(graph.BondedFor(addr)),
		yesno(graph.IsTrusted(addr, 2)),
		num.GNOTf(graph.Owed(addr)),
	)
	out += t.String()

	out += md.H2("Vouched for by")
	out += inbound(addr)

	out += md.H2("Vouches for")
	out += outbound(addr)

	out += "\n" + ui.Action("\U0001F91D Vouch for this address", "Vouch",
		"target", addr.String(), "reason", "") +
		" · " + ui.Action("\U0000274C Revoke mine", "Revoke", "target", addr.String()) + "\n"
	return out
}

func inbound(addr address) string {
	from := graph.VouchedBy(addr)
	if len(from) == 0 {
		return ui.Empty("Nobody vouches for this address.")
	}
	t := ui.NewTable("voucher", "reason", "bond", "mutual", "since")
	for _, f := range from {
		v, ok := graph.Get(f, addr)
		if !ok {
			continue
		}
		t.Row(
			md.Link(ui.AddrText(f), vo.AddrURL(realmPath, f)),
			ui.Cell(v.Reason),
			num.GNOTf(v.Bond),
			yesno(graph.Mutual(f, addr)),
			strconv.FormatInt(v.At, 10),
		)
	}
	return t.String()
}

func outbound(addr address) string {
	to := graph.VouchesOf(addr)
	if len(to) == 0 {
		return ui.Empty("This address vouches for nobody.")
	}
	t := ui.NewTable("for", "reason", "bond", "their vouchers")
	for _, target := range to {
		v, ok := graph.Get(addr, target)
		if !ok {
			continue
		}
		t.Row(
			md.Link(ui.AddrText(target), vo.AddrURL(realmPath, target)),
			ui.Cell(v.Reason),
			num.GNOTf(v.Bond),
			strconv.Itoa(graph.ScoreOf(target)),
		)
	}
	return t.String()
}

func yesno(b bool) string {
	if b {
		return "yes"
	}
	return "no"
}
