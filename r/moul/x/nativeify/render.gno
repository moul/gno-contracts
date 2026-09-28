package nativeify

import (
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/nt/ufmt/v0"
)

// Render lists the pairs. `?<base>` shows one.
func Render(path string) string {
	if path == "" {
		return renderIndex()
	}
	return renderOne(path)
}

func renderIndex() string {
	var sb strings.Builder
	sb.WriteString(md.H1("nativeify: wugnot, backwards"))
	sb.WriteString("\nwugnot takes a native coin and issues a GRC20, because a GRC20 can be " +
		"pulled by a contract and a native coin cannot. This realm does the other one: escrow " +
		"a GRC20, issue a native denom against it 1:1, and hand back something that moves with " +
		"no realm call, rides the `-send` envelope of a transaction, and shows up beside GNOT " +
		"on an account page.\n\n")
	sb.WriteString(md.Blockquote("What you give up is everything downstream of `Approve`. A " +
		"native coin has no allowance, so nothing can pull it: not an AMM, not an escrow, not " +
		"a subscription. And its issuer can always delete a balance."))
	sb.WriteString("\n")
	sb.WriteString(ufmt.Sprintf("Escrow account to approve: `%s`\n\n", home.String()))

	sb.WriteString(md.H2("Pairs") + "\n")
	t := ui.NewTable("base", "underlying", "denom", "escrowed", "issued", "solvent")
	for _, b := range bases {
		p := mustPair(b)
		escrowed, issued := Solvency(b)
		solvent := "yes"
		if escrowed < issued {
			solvent = "**NO**"
		}
		t.Row(md.Link(b, "/r/moul/x/nativeify/v0:"+b),
			ui.Cell(Underlying(b).GetSymbol()),
			md.InlineCode(ui.ShortN(p.denom, 20, 10)),
			ufmt.Sprintf("%d", escrowed), ufmt.Sprintf("%d", issued), solvent)
	}
	sb.WriteString(t.OrEmpty("Nothing wrapped yet.") + "\n")

	sb.WriteString(md.H2("Try it") + "\n")
	sb.WriteString("Claim play money, let this realm pull it, wrap, then send the result " +
		"around like any other coin:\n\n")
	sb.WriteString(md.LanguageCodeBlock("",
		"# 1. get RED\n"+
			"maketx call -pkgpath gno.land/r/moul/x/grc20faucet/v0 -func Claim\n\n"+
			"# 2. let this realm pull your RED\n"+
			"maketx call -pkgpath gno.land/r/moul/x/grc20faucet/v0 -func Approve \\\n"+
			ufmt.Sprintf("  -args RED -args %s -args 1000000\n\n", home.String())+
			"# 3. create the pair once, then wrap into it\n"+
			"maketx call -pkgpath "+Path+" -func Nativeify \\\n"+
			"  -args gno.land/r/moul/x/grc20faucet/v0.RED -args nred\n"+
			"maketx call -pkgpath "+Path+" -func Wrap -args nred -args 500000\n\n"+
			"# 4. it is an ordinary coin now: no realm call, no approval\n"+
			"maketx send -to <address> -send 1000/"+Path+":nred\n\n"+
			"# 5. redeem, by sending the coins back\n"+
			"maketx call -pkgpath "+Path+" -func Unwrap -args nred \\\n"+
			"  -send 1000/"+Path+":nred"))
	sb.WriteString("\nEvery denom here is described in [nativereg](/r/moul/x/nativereg/v0), " +
		"which is where a native coin says what it is, since the chain stores no name for it.\n")
	return sb.String()
}

func renderOne(base string) string {
	v := byBase.Get(base)
	if v == nil {
		return md.H1("404") + "\nThis realm does not issue " + md.InlineCode(base) + ".\n"
	}
	p := v.(*pair)
	under := Underlying(base)
	escrowed, issued := Solvency(base)

	t := ui.NewTable("", "")
	t.Row("denom", md.InlineCode(p.denom))
	t.Row("underlying", ui.Cell(under.GetName())+" ("+ui.Cell(under.GetSymbol())+")")
	t.Row("registry key", md.InlineCode(p.key))
	t.Row("decimals", ufmt.Sprintf("%d, a display hint only", under.GetDecimals()))
	t.Row("escrowed", ufmt.Sprintf("%d", escrowed))
	t.Row("issued", ufmt.Sprintf("%d", issued))
	t.Row("solvent", ufmt.Sprintf("%t", escrowed >= issued))
	t.Row("created at block", ufmt.Sprintf("%d", p.height))
	t.Row("created by", ui.Addr(p.creator))

	s := md.H1(ui.Inline(base)) + "\n" + t.String() + "\n"
	s += "Escrowed and issued are read from the GRC20 ledger and from the bank, not from " +
		"this realm's own bookkeeping. If they disagree, the disagreement is the answer.\n\n"
	s += md.LanguageCodeBlock("",
		"maketx call -pkgpath "+Path+" -func Wrap -args "+base+" -args <amount>\n"+
			"maketx call -pkgpath "+Path+" -func Unwrap -args "+base+" \\\n"+
			"  -send <amount>"+p.denom)
	return s
}
