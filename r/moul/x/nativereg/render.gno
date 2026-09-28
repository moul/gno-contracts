package nativereg

import (
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/nt/ufmt/v0"
)

// Render lists the registry. `?<denom>` shows one entry, `?<pkgpath>` shows
// everything one realm issues.
func Render(path string) string {
	if path == "" {
		return renderIndex()
	}
	if strings.HasPrefix(path, "/") {
		return renderDenom(path)
	}
	return renderIssuer(path)
}

func renderIndex() string {
	var sb strings.Builder
	sb.WriteString(md.H1("nativereg: what a native denom means"))
	sb.WriteString("\nA realm-issued coin is a string and a balance. The chain stores no name, " +
		"no symbol and no decimals for it, so this realm does. An issuer registers its own " +
		"denoms and nobody else's: the package path is embedded in the denom, and that is " +
		"the whole authorization.\n\n")

	t := ui.NewTable("denom", "symbol", "name", "decimals", "issuer")
	for _, e := range List() {
		t.Row(md.InlineCode(ui.ShortN(e.Denom, 22, 12)), ui.Cell(e.Symbol), ui.Cell(e.Name),
			ufmt.Sprintf("%d", e.Decimals), md.Link(ui.Short(e.Issuer), "/"+strings.TrimPrefix(e.Issuer, "gno.land/")))
	}
	sb.WriteString(md.H2("Registered"))
	sb.WriteString("\n" + t.OrEmpty("Nothing registered yet.") + "\n")

	sb.WriteString(md.H2("Register your own"))
	sb.WriteString("\nFrom inside the realm that issues the coin, never from a wallet:\n\n")
	sb.WriteString(md.LanguageCodeBlock("go",
		"import \"gno.land/r/moul/x/nativereg/v0\"\n\n"+
			"func init(cur realm) {\n"+
			"\tnativereg.Register(cross(cur), Denom, \"My Coin\", \"MINE\", 6,\n"+
			"\t\t\"one line about what it is for\")\n"+
			"}"))
	sb.WriteString("\n" + md.Italic("Decimals is a display hint. The bank counts whole units and "+
		"knows nothing about divisibility.") + "\n")
	return sb.String()
}

func renderDenom(denom string) string {
	e, ok := Get(denom)
	if !ok {
		return md.H1("Not registered") + "\n" + md.InlineCode(denom) +
			" has said nothing about itself.\n\nIts issuer is " +
			md.InlineCode(safeIssuer(denom)) + ", and only that realm can change it.\n"
	}

	t := ui.NewTable("", "")
	t.Row("denom", md.InlineCode(e.Denom))
	t.Row("issuer", md.InlineCode(e.Issuer))
	t.Row("name", ui.Cell(e.Name))
	t.Row("symbol", ui.Cell(e.Symbol))
	t.Row("decimals", ufmt.Sprintf("%d (display hint)", e.Decimals))
	t.Row("registered at block", ufmt.Sprintf("%d", e.Height))
	t.Row("revisions", ufmt.Sprintf("%d", e.Revisions))

	s := md.H1(ui.Inline(e.Symbol)) + "\n"
	if e.Doc != "" {
		s += ui.Inline(e.Doc) + "\n\n"
	}
	s += t.String() + "\n"
	s += md.Blockquote("The issuer can rewrite every row but the first two, and can remove "+
		"this coin from any balance at any time. That is what a realm-issued coin is.") + "\n"
	return s
}

func renderIssuer(pkgPath string) string {
	entries := ByIssuer(pkgPath)
	s := md.H1("Issued by "+ui.Inline(pkgPath)) + "\n"
	t := ui.NewTable("denom", "symbol", "name")
	for _, e := range entries {
		t.Row(md.InlineCode(ui.ShortN(e.Denom, 22, 12)), ui.Cell(e.Symbol), ui.Cell(e.Name))
	}
	return s + t.OrEmpty("This realm has registered nothing here.") + "\n"
}

// safeIssuer is IssuerOf for a Render, which must never abort on a path a reader
// typed into the URL bar.
func safeIssuer(denom string) string {
	if !strings.HasPrefix(denom, "/") {
		return "unknown (not a realm denom)"
	}
	i := strings.LastIndex(denom, ":")
	if i < 1 {
		return "unknown (not a realm denom)"
	}
	return denom[1:i]
}
