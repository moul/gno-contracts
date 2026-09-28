package reactions

import (
	"strconv"
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	rx "gno.land/p/moul/reactions/v0"
)

// maxListed caps the board index. The number of pages is unbounded (anyone can
// react to any key), and a Render that grows with it would eventually be too
// expensive to serve. The cap is on the INDEX only: every page keeps its own
// view at /r/moul/reactions/v0:<page>, whether or not it is listed here.
const maxListed = 25

// Render serves two views:
//
//	""       the getting-started page: how to embed the block, plus the board
//	"<page>" one page's tally, where <page> is a package path
//
// The page view's path is the key itself, so the link under any embedded block
// is just this realm's path, a colon, and the page. That is why a page key may
// contain a colon of its own: "gno.land/r/you/blog:hello" reads back whole.
func Render(path string) string {
	if path == "" {
		return renderHome()
	}
	if !rx.ValidPage(path) {
		return "# Not a page\n\n" + ui.Inline(path) + " is not a page key: a key is a " +
			"package path, lowercase ASCII, at most " + strconv.Itoa(rx.MaxPageLen) +
			" bytes.\n\n[Back to the board](" + selfURL() + ")\n"
	}
	return renderPage(path)
}

// selfURL is this realm's own gnoweb path, derived from realmPath the same way
// every link in the block is, so there is one rule and not two. A function and
// not a package-level var: a package-level var in a realm is realm STATE,
// persisted and re-read on every call, which is a strange thing for a string
// the compiler could have folded.
func selfURL() string { return rx.RealmURL(realmPath) }

func renderHome() string {
	var b strings.Builder

	b.WriteString("# Reactions\n\n")
	b.WriteString("A reaction block any realm can embed. One line in your `Render`, no state ")
	b.WriteString("on your side, and readers get one-click reactions keyed on the page they ")
	b.WriteString("are looking at.\n\n")
	b.WriteString("It is not a comment system, on purpose. There is no text field anywhere, ")
	b.WriteString("which is what lets it run with no moderation: a closed palette, one ")
	b.WriteString("reaction per address per page, changeable and removable.\n\n")

	b.WriteString("## It looks like this\n\n")
	b.WriteString(blockFor(realmPath))
	b.WriteString("\nThat block is live and it is this realm's own page. Click one.\n\n")

	b.WriteString("## Add it to your realm\n\n")
	b.WriteString("```go\n")
	b.WriteString("import \"" + realmPath + "\"\n\n")
	b.WriteString("func Render(path string) string {\n")
	b.WriteString("\treturn body + reactions.RenderBlock()\n")
	b.WriteString("}\n")
	b.WriteString("```\n\n")
	b.WriteString("That is the whole integration. `RenderBlock` takes no argument because it ")
	b.WriteString("does not need one: a plain read exported by one realm and called by ")
	b.WriteString("another opens no realm frame, so it sees YOUR path and uses it as the ")
	b.WriteString("page key. Nothing to register, nothing to configure.\n\n")
	b.WriteString("For one block per article rather than one per realm, name the page ")
	b.WriteString("yourself with the path you already serve:\n\n")
	b.WriteString("```go\n")
	b.WriteString("return body + reactions.RenderBlockFor(\"gno.land/r/you/blog:\" + path)\n")
	b.WriteString("```\n\n")
	b.WriteString("Reactions are recorded here, not in your realm, so redeploying yours ")
	b.WriteString("never loses them.\n\n")

	b.WriteString("## The palette\n\n")
	t := ui.NewTable("key", "")
	for _, k := range rx.Keys() {
		t.Row("`"+k+"`", rx.Emoji(k))
	}
	b.WriteString(t.String())
	b.WriteString("\nSix, and the set is closed. `React` aborts on anything else, which is ")
	b.WriteString("the entire moderation policy.\n\n")

	b.WriteString("## The board\n\n")
	b.WriteString(renderBoard())

	return b.String()
}

// renderBoard lists pages in key order, not by activity. Key order is the order
// the tree already walks, so the listing is stable between identical calls;
// ranking would need a second index maintained on every write, which is a lot
// of machinery for a table nobody navigates by.
func renderBoard() string {
	n := board.Pages()
	if n == 0 {
		return ui.Empty("No page has been reacted to yet.")
	}

	t := ui.NewTable("page", "reactions", "last")
	board.Each(func(page string, p *rx.Page) bool {
		key, who, _ := p.Last()
		last := "-"
		if key != "" {
			last = rx.Emoji(key) + " " + ui.Addr(who)
		}
		t.Row(
			"["+ui.Cell(page)+"]("+rx.PageURL(realmPath, page)+")",
			strconv.Itoa(p.Total()),
			last,
		)
		return t.Len() >= maxListed
	})

	out := t.String()
	if n > maxListed {
		out += "\n" + strconv.Itoa(n) + " pages in total, " + strconv.Itoa(maxListed) +
			" shown. Every page has its own view at `" + selfURL() + ":<page>`.\n"
	}
	return out
}

func renderPage(page string) string {
	p := board.Page(page)

	var b strings.Builder
	b.WriteString("# " + ui.Inline(page) + "\n\n")
	b.WriteString(blockFor(page))
	b.WriteString("\n")

	if p.Total() == 0 {
		b.WriteString(ui.Empty("Nobody is reacting to this page right now."))
	} else {
		t := ui.NewTable("", "reaction", "addresses")
		for _, k := range rx.Keys() {
			if c := p.Count(k); c > 0 {
				t.Row(rx.Emoji(k), "`"+k+"`", strconv.Itoa(c))
			}
		}
		b.WriteString(t.String())
	}

	if key, who, height := p.Last(); key != "" {
		b.WriteString("\nLast reaction: " + rx.Emoji(key) + " by " + ui.Addr(who) +
			" at height " + strconv.FormatInt(height, 10) + ".\n")
	}

	b.WriteString("\n" + ui.ActionIn(realmPath, "Remove my reaction", "Unreact", "page", page))
	b.WriteString(" · [The board](" + selfURL() + ")\n")
	return b.String()
}
