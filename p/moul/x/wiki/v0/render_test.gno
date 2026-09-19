package wiki

import (
	"strings"
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func fixture(t *testing.T) (*Wiki, Ctx) {
	t.Helper()
	w := New(2, DefaultMaxBody)
	edit(t, w, 1, alice, "Gno land", "A chain.\n\nSee [[Tendermint2]] and [[Absent page]].\n\n[[Category:Chains]]\n", "create")
	edit(t, w, 2, bob, "Gno land", "A smart-contract chain.\n\nSee [[Tendermint2]].\n\n[[Category:Chains]]\n", "tighten")
	edit(t, w, 3, alice, "Tendermint2", "The consensus engine.\n", "create")
	return w, Ctx{Base: "/r/moul/x/wiki/v0", Exists: w.Exists}
}

func act(fn string, args ...string) string {
	out := "/r/moul/x/wiki/v0$help&func=" + fn
	for i := 0; i+1 < len(args); i += 2 {
		out += "&" + args[i] + "=" + args[i+1]
	}
	return out
}

func TestRenderArticle(t *testing.T) {
	w, c := fixture(t)
	p, _ := w.Page("Gno land")
	out := RenderArticle(c, w, p, act)

	uassert.True(t, strings.Contains(out, "# Gno land"), "heading")
	uassert.True(t, strings.Contains(out, "A smart-contract chain."), "body text")
	uassert.True(t, strings.Contains(out, "[Tendermint2](/r/moul/x/wiki/v0:Tendermint2)"), "resolved wikilink")
	uassert.False(t, strings.Contains(out, "[[Tendermint2]]"), "no raw wikilink survives")
	uassert.True(t, strings.Contains(out, "**Categories:**"), "category footer")
	uassert.True(t, strings.Contains(out, "[Chains](/r/moul/x/wiki/v0:Category:Chains)"), "category link")
	uassert.True(t, strings.Contains(out, "func=Edit"), "edit action")
	uassert.True(t, strings.Contains(out, "GNOT of storage deposit"), "cost is shown to the reader")
}

func TestRenderArticleWithoutActionsHasNoEditControls(t *testing.T) {
	w, c := fixture(t)
	p, _ := w.Page("Gno land")
	out := RenderArticle(c, w, p, nil)
	uassert.False(t, strings.Contains(out, "func=Edit"), "a nil Action renders a read-only page")
}

func TestRenderArticleEscapesHostileMarkdown(t *testing.T) {
	w := New(2, DefaultMaxBody)
	body := "<script>alert(1)</script>\n\n# Fake realm heading\n"
	edit(t, w, 1, alice, "Hostile", body, "")
	p, _ := w.Page("Hostile")
	out := RenderArticle(Ctx{Base: "/r/moul/x/wiki/v0"}, w, p, nil)

	uassert.True(t, strings.Contains(out, `\<script>`),
		"an HTML block is escaped, not dropped: the reader still sees what was written")
	uassert.False(t, strings.Contains(out, "\n<script>"),
		"no unescaped HTML block reaches the renderer")
	// The realm's own footer must still be there: a CommonMark HTML block of
	// type 1-5 does not close on a blank line, so an unescaped one would
	// swallow every byte the realm appends after the body.
	uassert.True(t, strings.Contains(out, "GNOT of storage deposit"),
		"user content cannot absorb the realm chrome that follows it")
}

func TestRenderMissing(t *testing.T) {
	w, c := fixture(t)
	out := RenderMissing(c, w, MustParseTitle("Absent page"), act)
	uassert.True(t, strings.Contains(out, "does not exist yet"))
	uassert.True(t, strings.Contains(out, "func=Edit"))
	// The first revision of Gno land linked here; the second dropped the link,
	// so nothing should be listed.
	uassert.True(t, strings.Contains(out, "does not exist yet"))
}

func TestRenderHistory(t *testing.T) {
	w, c := fixture(t)
	p, _ := w.Page("Gno land")
	out := RenderHistory(c, p, 0, 10, act)

	uassert.True(t, strings.Contains(out, "# History of Gno land"))
	uassert.True(t, strings.Contains(out, "**rev 2**"))
	uassert.True(t, strings.Contains(out, "**rev 1**"))
	uassert.True(t, strings.Contains(out, "from=1&to=2"), "consecutive revisions get a diff link")
	uassert.True(t, strings.Contains(out, "func=Revert"))
}

func TestRenderDiff(t *testing.T) {
	w, c := fixture(t)
	p, _ := w.Page("Gno land")
	h := p.History(0, 2)
	out := RenderDiff(c, p, h[1], h[0])

	uassert.True(t, strings.Contains(out, "rev 1 → rev 2"))
	uassert.True(t, strings.Contains(out, "-A chain."))
	uassert.True(t, strings.Contains(out, "+A smart-contract chain."))
	uassert.True(t, strings.Contains(out, "```diff"))
}

func TestRenderDiffRefusesEvictedBodies(t *testing.T) {
	w := New(1, DefaultMaxBody)
	edit(t, w, 1, alice, "A", "one\n", "")
	edit(t, w, 2, alice, "A", "two\n", "")
	p, _ := w.Page("A")
	h := p.History(0, 2)
	out := RenderDiff(Ctx{Base: "/r/moul/x/wiki/v0"}, p, h[1], h[0])
	uassert.True(t, strings.Contains(out, "no longer held on chain"),
		"an evicted body must be explained, not rendered as an empty diff")
}

func TestRenderRawShowsTheHashAReaderNeeds(t *testing.T) {
	w, c := fixture(t)
	p, _ := w.Page("Gno land")
	out := RenderRaw(c, p, p.Head())
	uassert.True(t, strings.Contains(out, p.Head().Hash), "the full hash, so the bytes can be verified")
	uassert.True(t, strings.Contains(out, "[[Tendermint2]]"), "raw view shows the source, unrewritten")
}

func TestRenderIndexAndSpecials(t *testing.T) {
	w, c := fixture(t)

	idx := RenderIndex(c, w, 10)
	uassert.True(t, strings.Contains(idx, "2 pages"))
	uassert.True(t, strings.Contains(idx, "Recent changes"))

	all := RenderAllPages(c, w, NSMain, 0, 10)
	uassert.True(t, strings.Contains(all, "[Gno land]"))
	uassert.True(t, strings.Contains(all, "[Tendermint2]"))

	cats := RenderCategories(c, w)
	uassert.True(t, strings.Contains(cats, "[Chains](/r/moul/x/wiki/v0:Category:Chains) (1)"))

	cat := RenderCategory(c, w, MustParseTitle("Category:Chains"), nil, nil)
	uassert.True(t, strings.Contains(cat, "no description page"))
	uassert.True(t, strings.Contains(cat, "Pages in this category (1)"))

	back := RenderBacklinks(c, w, MustParseTitle("Tendermint2"))
	uassert.True(t, strings.Contains(back, "[Gno land]"))

	stats := RenderStats(c, w)
	uassert.True(t, strings.Contains(stats, "bodies kept per page: 2"))
}

func TestRenderBlankedPage(t *testing.T) {
	w, c := fixture(t)
	now, h := at(9)
	w.Blank(mod, now, h, "Gno land", "policy")
	p, _ := w.Page("Gno land")
	out := RenderArticle(c, w, p, nil)
	uassert.True(t, strings.Contains(out, "was blanked"))
	uassert.True(t, strings.Contains(out, "view history"))
}

func TestRenderRedirect(t *testing.T) {
	w, c := fixture(t)
	edit(t, w, 4, alice, "Gno", "#REDIRECT [[Gno land]]\n", "")
	p, _ := w.Page("Gno")
	out := RenderArticle(c, w, p, nil)
	uassert.True(t, strings.Contains(out, "Redirects to [Gno land](/r/moul/x/wiki/v0:Gno_land)"))
}
