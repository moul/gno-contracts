package moultest

import (
	"chain/runtime"
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/nt/ufmt/v0"
)

// Render shows the coin, what is left under each cap, and the tip board.
// `?<address>` adds that address's balance and claim state.
func Render(path string) string {
	var sb strings.Builder

	sb.WriteString(md.H1("moultest: a native coin you can help yourself to"))
	sb.WriteString("\nNot a GRC20. The chain's bank holds it, so it moves with a plain send, " +
		"shows up beside GNOT on any account page, and can ride the `-send` envelope of a " +
		"transaction. There is no ledger in this realm and no registry entry anywhere.\n\n")
	sb.WriteString(md.LanguageCodeBlock("", Denom))
	sb.WriteString("\n")

	sb.WriteString(renderSupply())
	sb.WriteString(renderAccount(path))
	sb.WriteString(renderTips())
	sb.WriteString(renderUsage())
	return sb.String()
}

func renderSupply() string {
	t := ui.NewTable("", "amount", "cap", "left")
	t.Row("issued, ever", ufmt.Sprintf("%d", issued), ufmt.Sprintf("%d", MaxSupply),
		ufmt.Sprintf("%d", MaxSupply-issued))
	t.Row("circulating", ufmt.Sprintf("%d", Circulating()), "", "")
	t.Row("burned", ufmt.Sprintf("%d", burned), "", "")
	t.Row("accounts", ufmt.Sprintf("%d", accounts.Size()), "", "")

	s := md.H2("Supply") + "\n" + t.String()
	s += "\n" + ufmt.Sprintf(
		"`%d` per claim, once every `%d` blocks, `%d` per address for life. "+
			"Burning lowers what circulates and gives back no headroom, "+
			"or claim-burn-claim would be an unlimited faucet.\n",
		ClaimAmount, ClaimEvery, MaxPerAccount)
	return s + "\n"
}

func renderAccount(path string) string {
	who := address(path)
	if path == "" || !who.IsValid() {
		return ""
	}

	s := md.H2("Account "+ui.AddrText(who)) + "\n"
	t := ui.NewTable("", "")
	t.Row("address", ui.AddrFull(who))
	t.Row("balance", ufmt.Sprintf("%d moultest", BalanceOf(who)))
	t.Row("claimed for life", ufmt.Sprintf("%d of %d", ClaimedBy(who), MaxPerAccount))

	next, ever := NextClaim(who)
	switch {
	case !ever:
		t.Row("next claim", "now, this address has never claimed")
	case runtime.ChainHeight() >= next:
		t.Row("next claim", "now")
	default:
		t.Row("next claim", ufmt.Sprintf("block %d (%d to go)", next, next-runtime.ChainHeight()))
	}
	return s + t.String() + "\n"
}

func renderTips() string {
	s := md.H2("Tips") + "\n"
	if len(tips) == 0 {
		return s + ui.Empty("Nobody has tipped anybody yet.") + "\n"
	}
	t := ui.NewTable("block", "from", "to", "amount", "note")
	// Most recent first; the slice keeps them oldest first.
	for i := len(tips) - 1; i >= 0; i-- {
		e := tips[i]
		t.Row(ufmt.Sprintf("%d", e.height), ui.Addr(e.from), ui.Addr(e.to),
			ufmt.Sprintf("%d", e.amount), ui.Cell(e.note))
	}
	return s + t.String() + "\n"
}

func renderUsage() string {
	s := md.H2("Use it") + "\n"
	s += md.BulletItem(ui.Action("Claim "+ufmt.Sprintf("%d moultest", ClaimAmount), "Claim"))
	s += "\n"
	s += "Then it is an ordinary coin, and moving it needs nothing from this realm:\n\n"
	s += md.LanguageCodeBlock("", ""+
		"# help yourself\n"+
		"gnokey maketx call -pkgpath "+Path+" -func Claim ...\n\n"+
		"# send some to a friend: a bank message, no realm call at all\n"+
		"gnokey maketx send -to <address> -send 2500"+Denom+" ...\n\n"+
		"# tip somebody through this realm, note included. The coin rides the\n"+
		"# envelope, which is the thing a GRC20 cannot do.\n"+
		"gnokey maketx call -pkgpath "+Path+" -func Tip \\\n"+
		"  -args <address> -args \"nice work\" -send 1000"+Denom+" ...\n\n"+
		"# destroy some of your own\n"+
		"gnokey maketx call -pkgpath "+Path+" -func Burn -args 1000 ...")
	s += "\n" + md.Italic("Worthless by construction. Do not price it.") + "\n"
	return s
}
