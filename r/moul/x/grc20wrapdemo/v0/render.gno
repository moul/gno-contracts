package grc20wrapdemo

import (
	"gno.land/p/nt/ufmt/v0"
)

func Render(path string) string {
	if path == "" {
		return renderIndex()
	}
	return renderOne(path)
}

func renderIndex() string {
	s := "# GRC20 wrapper factory\n\n"
	s += "Wrap any token registered in [grc20reg](/r/nt/grc20reg/v0) into a new one "
	s += "with a different personality, or fuse two into one. Permissionless: "
	s += "no allowlist, no owner, no authority over anybody's balance.\n\n"
	s += ufmt.Sprintf("Escrow account to approve: `%s`\n\n", home.String())

	s += "## Modes\n\n"
	s += "| mode | what the wrapped token does |\n"
	s += "|---|---|\n"
	s += "| `plain` | 1:1 custody receipt |\n"
	s += "| `kilo` | 1 underlying unit becomes 1000 wrapped, +3 decimals |\n"
	s += "| `soulbound` | wrap and unwrap freely, never transferable |\n"
	s += "| `pool` | shares in the escrow; `Donate` pays every holder at once |\n"
	s += "| `sticky` | `pool` plus a 1% exit fee, left behind for whoever stays |\n"
	s += "| `fusion` | one meta-token backed by a fixed bundle of two others |\n"

	s += "\n## Issued here\n\n"
	if len(created) == 0 {
		s += "Nothing yet. Be the first.\n"
	} else {
		s += "| symbol | mode | backing | supply | registry key |\n"
		s += "|---|---|---|---|---|\n"
		for _, sym := range created {
			e := must(sym)
			s += ufmt.Sprintf("| [%s](/r/moul/x/grc20wrapdemo/v0:%s) | %s | %s | %d | `%s` |\n",
				e.symbol, e.symbol, e.mode, e.backing(), e.token().TotalSupply(), e.key)
		}
	}

	s += "\n## Try it\n\n"
	s += "Claim play money from [the faucet](/r/moul/x/grc20faucet/v0), let this realm\n"
	s += "spend it, then wrap:\n\n"
	s += "```\n"
	s += "# 1. get RED and BLUE\n"
	s += "maketx call -pkgpath gno.land/r/moul/x/grc20faucet/v0 -func Claim\n\n"
	s += "# 2. let this realm pull your RED\n"
	s += "maketx call -pkgpath gno.land/r/moul/x/grc20faucet/v0 -func Approve \\\n"
	s += ufmt.Sprintf("  -args RED -args %s -args 1000000\n\n", home.String())
	s += "# 3. create a pool wrapper over RED, then deposit into it\n"
	s += "maketx call -pkgpath gno.land/r/moul/x/grc20wrapdemo/v0 -func NewWrapper \\\n"
	s += "  -args gno.land/r/moul/x/grc20faucet/v0.RED -args pool -args pRED\n"
	s += "maketx call -pkgpath gno.land/r/moul/x/grc20wrapdemo/v0 -func Deposit \\\n"
	s += "  -args pRED -args 500000\n"
	s += "```\n\n"
	s += "Built on [p/moul/x/grc20wrap](/p/moul/x/grc20wrap/v0).\n"
	return s
}

func renderOne(symbol string) string {
	e := byName.Get(symbol)
	if e == nil {
		return "# 404\n\nThis realm has not issued `" + symbol + "`.\n"
	}
	en := e.(*entry)

	s := ufmt.Sprintf("# %s\n\n", en.symbol)
	if en.vault != nil {
		s += en.vault.Summary()
	} else {
		s += en.basket.Summary()
	}
	s += ufmt.Sprintf("\n- mode: `%s`\n", en.mode)
	s += ufmt.Sprintf("- registry key: `%s`\n", en.key)
	s += ufmt.Sprintf("- created by: `%s` at block %d\n", en.creator.String(), en.height)
	s += "\n[back to the index](/r/moul/x/grc20wrapdemo/v0)\n"
	return s
}

// backing names what an entry is redeemable for, for the index table.
func (e *entry) backing() string {
	if e.vault != nil {
		return e.vault.Underlying().GetSymbol()
	}
	out := ""
	for i := 0; i < e.basket.Legs(); i++ {
		tok, per, _ := e.basket.Leg(i)
		if i > 0 {
			out += " + "
		}
		out += ufmt.Sprintf("%dx%s", per, tok.GetSymbol())
	}
	return out
}
