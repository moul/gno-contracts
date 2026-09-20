package wiki

import (
	"strings"

	"gno.land/p/moul/md/v0"
	"gno.land/p/nt/markdown/sanitize/v0"
	"gno.land/p/nt/ufmt/v0"
)

// DepositPerByte is the storage deposit a realm write locks per byte, in
// ugnot (gnolang/gno#6171). It is used only to show a reader what a page
// costs; the chain, not this package, does the accounting.
const DepositPerByte = 100

// Action builds a transaction link for a realm function. The realm supplies
// it (txlink.Realm("…").Call is the usual value); a nil Action renders a page
// with no edit controls, which is what an archived or read-only mirror wants.
type Action func(fn string, args ...string) string

// RenderArticle renders a page for reading: the sanitized body with its
// wikilinks resolved, a header identifying the current revision, and a footer
// with categories and cost.
func RenderArticle(c Ctx, w *Wiki, p *Page, act Action) string {
	var out strings.Builder
	out.WriteString(md.H1(p.Title.String()))

	if p.head == nil {
		out.WriteString(md.Paragraph("_This page has no revisions._"))
		return out.String()
	}
	out.WriteString(articleMeta(c, w, p, act))

	if p.Blanked {
		out.WriteString(md.Blockquote("This page was blanked. Its history is still on chain: " +
			md.Link("view history", c.Sub(p.Title, "history"))))
		return out.String()
	}

	body, kept := p.Body()
	switch {
	case !kept:
		out.WriteString(md.Blockquote("The current revision's body is no longer held on chain. " +
			"Recover it from the transaction that wrote it and check it against `" + p.head.ShortHash() + "`."))
	case p.redirect != "":
		out.WriteString(md.Paragraph("Redirects to " + md.Link(p.redirect, escapeURL(c.Base+":"+strings.ReplaceAll(p.redirect, " ", "_")))))
	default:
		// sanitize.BlockRich wraps its output in blank lines on both sides,
		// and that padding is load-bearing: a CommonMark HTML block of type
		// 6 or 7 is not escaped in any mode, and without the blank line it
		// would swallow the footer this function appends next. Do not trim
		// it to tidy the output.
		out.WriteString(RewriteLinks(c, sanitize.BlockRich(body)))
	}

	out.WriteString(articleFooter(c, w, p))
	return out.String()
}

func articleMeta(c Ctx, w *Wiki, p *Page, act Action) string {
	h := p.head
	parts := []string{
		ufmt.Sprintf("rev %d", h.ID),
		h.Time.Format("2006-01-02 15:04"),
		"by " + shortAddr(h.Author),
	}
	if p.Protection != Open {
		parts = append(parts, p.Protection.String())
	}
	line := strings.Join(parts, " · ")

	nav := []string{
		md.Link("history", c.Sub(p.Title, "history")),
		md.Link("source", c.Sub(p.Title, "raw")),
		md.Link("what links here", c.SpecialURL("Backlinks", "page="+p.Title.Slug())),
	}
	if act != nil {
		nav = append(nav, md.Link("edit", act("Edit", "title", p.Title.String())))
	}
	// The count sits outside the link text on purpose: md.Link sanitizes its
	// label, so parentheses inside it would render as "\(1\)".
	nav = append(nav, md.Link("discussion", c.Sub(p.Title, "talk"))+
		ufmt.Sprintf(" (%d)", w.NumComments(p.Title)))
	return md.Paragraph(line + "\n\n" + strings.Join(nav, " · "))
}

func articleFooter(c Ctx, w *Wiki, p *Page) string {
	var out strings.Builder
	out.WriteString(md.HorizontalRule())

	if len(p.cats) > 0 {
		cats := []string{}
		for _, key := range p.cats {
			t := Title{NS: NSCategory, Name: key[len(NSCategory.Prefix()):]}
			cats = append(cats, md.Link(t.Name, c.URL(t)))
		}
		out.WriteString(md.Paragraph("**Categories:** " + strings.Join(cats, " · ")))
	}

	held := 0
	p.revs.Iterator(0, p.revs.Size()-1, func(_ int, v any) bool {
		r := v.(*Revision)
		if r.kept {
			held += r.Size
		}
		return false
	})
	out.WriteString(md.Paragraph(ufmt.Sprintf(
		"%s · %d bytes of text held on chain · %s of storage deposit · %s link here",
		plural(p.NumRevisions(), "revision", "revisions"),
		held, formatGNOT(held*DepositPerByte),
		plural(len(w.Backlinks(p.Title)), "page", "pages"))))
	return out.String()
}

// RenderMissing renders the stub shown for a title with no page: the red-link
// destination, listing whoever already points at it.
func RenderMissing(c Ctx, w *Wiki, t Title, act Action) string {
	var out strings.Builder
	out.WriteString(md.H1(t.String()))
	out.WriteString(md.Paragraph("_This page does not exist yet._"))
	if act != nil {
		out.WriteString(md.Paragraph(md.Link("Create it", act("Edit", "title", t.String()))))
	}
	if in := w.Backlinks(t); len(in) > 0 {
		out.WriteString(md.H2("Pages that already link here"))
		out.WriteString(titleList(c, in))
	}
	return out.String()
}

// RenderHistory renders a page's revision list, newest first.
func RenderHistory(c Ctx, p *Page, offset, count int, act Action) string {
	var out strings.Builder
	out.WriteString(md.H1("History of " + p.Title.String()))
	out.WriteString(md.Paragraph(md.Link("← back to the article", c.URL(p.Title))))

	revs := p.History(offset, count)
	if len(revs) == 0 {
		out.WriteString(md.Paragraph("_No revisions in this range._"))
		return out.String()
	}
	items := []string{}
	for _, r := range revs {
		line := ufmt.Sprintf("**rev %d** · %s · %s · %s · %d bytes · `%s`",
			r.ID, r.Time.Format("2006-01-02 15:04"), shortAddr(r.Author), string(r.Kind), r.Size, r.ShortHash())
		if r.Summary != "" {
			line += "\n\n" + sanitize.InlineText(r.Summary)
		}
		extra := []string{}
		if r.Prev != 0 {
			extra = append(extra, md.Link("diff", c.Sub(p.Title, "diff")+"?from="+ufmt.Sprintf("%d", r.Prev)+"&to="+ufmt.Sprintf("%d", r.ID)))
		}
		if r.kept {
			extra = append(extra, md.Link("view", c.Sub(p.Title, "rev")+"/"+ufmt.Sprintf("%d", r.ID)))
			if act != nil {
				extra = append(extra, md.Link("revert to this", act("Revert",
					"title", p.Title.String(), "rev", ufmt.Sprintf("%d", r.ID))))
			}
		} else {
			extra = append(extra, "_body evicted_")
		}
		items = append(items, line+"\n\n"+strings.Join(extra, " · "))
	}
	out.WriteString(md.BulletList(items))

	if offset+len(revs) < p.NumRevisions() {
		out.WriteString(md.Paragraph(md.Link("older →",
			c.Sub(p.Title, "history")+"?offset="+ufmt.Sprintf("%d", offset+count))))
	}
	return out.String()
}

// RenderRevision renders one stored revision verbatim.
func RenderRevision(c Ctx, p *Page, r *Revision) string {
	var out strings.Builder
	out.WriteString(md.H1(ufmt.Sprintf("%s: revision %d", p.Title.String(), r.ID)))
	out.WriteString(md.Paragraph(ufmt.Sprintf("%s · %s · `%s`",
		r.Time.Format("2006-01-02 15:04"), shortAddr(r.Author), r.Hash)))
	body, kept := r.Body()
	if !kept {
		out.WriteString(md.Blockquote("This revision's body is no longer held on chain."))
		return out.String()
	}
	out.WriteString(RewriteLinks(c, sanitize.BlockRich(body)))
	return out.String()
}

// RenderRaw renders a revision's source inside a code block, which is what a
// reader needs before editing and what a verifier needs to re-hash.
func RenderRaw(c Ctx, p *Page, r *Revision) string {
	var out strings.Builder
	out.WriteString(md.H1(ufmt.Sprintf("Source of %s (rev %d)", p.Title.String(), r.ID)))
	out.WriteString(md.Paragraph("sha256 `" + r.Hash + "`"))
	body, kept := r.Body()
	if !kept {
		out.WriteString(md.Blockquote("This revision's body is no longer held on chain."))
		return out.String()
	}
	out.WriteString(sanitize.CodeBlock(body))
	out.WriteString(md.Paragraph(md.Link("← back to the article", c.URL(p.Title))))
	return out.String()
}

// RenderDiff renders the line diff between two revisions of a page.
func RenderDiff(c Ctx, p *Page, from, to *Revision) string {
	var out strings.Builder
	out.WriteString(md.H1(ufmt.Sprintf("%s: rev %d → rev %d", p.Title.String(), from.ID, to.ID)))

	a, okA := from.Body()
	b, okB := to.Body()
	if !okA || !okB {
		out.WriteString(md.Blockquote("One of these revisions' bodies is no longer held on chain, so the diff cannot be computed. " +
			"Their hashes are `" + from.ShortHash() + "` and `" + to.ShortHash() + "`."))
		return out.String()
	}

	lines, exact := DiffLines(a, b)
	added, removed := DiffStat(lines)
	note := ufmt.Sprintf("+%d −%d lines", added, removed)
	if !exact {
		note += " · changed region larger than " + ufmt.Sprintf("%d", DiffMaxLines) + " lines, shown as a block replacement"
	}
	out.WriteString(md.Paragraph(note))

	var d strings.Builder
	for _, l := range lines {
		switch l.Op {
		case OpInsert:
			d.WriteString("+" + l.Text + "\n")
		case OpDelete:
			d.WriteString("-" + l.Text + "\n")
		default:
			d.WriteString(" " + l.Text + "\n")
		}
	}
	out.WriteString(sanitize.LanguageCodeBlock("diff", d.String()))
	out.WriteString(md.Paragraph(md.Link("← back to the article", c.URL(p.Title))))
	return out.String()
}

// RenderIndex renders the wiki's front page: recent changes and a page count.
func RenderIndex(c Ctx, w *Wiki, recent int) string {
	var out strings.Builder
	s := w.Stats()
	out.WriteString(md.H1("Wiki"))
	out.WriteString(md.Paragraph(strings.Join([]string{
		md.Link("all pages", c.SpecialURL("AllPages", "")),
		md.Link("categories", c.SpecialURL("Categories", "")),
		md.Link("recent changes", c.SpecialURL("RecentChanges", "")),
		md.Link("stats", c.SpecialURL("Stats", "")),
	}, " · ")))
	out.WriteString(md.Paragraph(ufmt.Sprintf("%d pages · %d revisions · %d bytes on chain",
		s.Pages, s.Revisions, s.BytesHeld)))
	out.WriteString(md.H2("Recent changes"))
	out.WriteString(changeList(c, w.Recent(recent)))
	return out.String()
}

// RenderRecent renders the recent-changes feed.
func RenderRecent(c Ctx, w *Wiki, n int) string {
	return md.H1("Recent changes") + changeList(c, w.Recent(n))
}

// RenderAllPages renders the page index for a namespace prefix.
func RenderAllPages(c Ctx, w *Wiki, ns Namespace, offset, count int) string {
	var out strings.Builder
	out.WriteString(md.H1("All pages"))

	tabs := []string{}
	for i := range namespaces {
		n := Namespace(i)
		if n == NSSpecial {
			continue
		}
		label := n.String()
		if label == "" {
			label = "Articles"
		}
		if n == ns {
			label = "**" + label + "**"
		}
		tabs = append(tabs, md.Link(label, c.SpecialURL("AllPages", "ns="+ufmt.Sprintf("%d", i))))
	}
	out.WriteString(md.Paragraph(strings.Join(tabs, " · ")))

	titles := w.Titles(ns.Prefix(), offset, count)
	if len(titles) == 0 {
		out.WriteString(md.Paragraph("_No pages in this namespace._"))
		return out.String()
	}
	out.WriteString(titleList(c, titles))
	if len(titles) == count {
		out.WriteString(md.Paragraph(md.Link("next →",
			c.SpecialURL("AllPages", ufmt.Sprintf("ns=%d&offset=%d", uint8(ns), offset+count)))))
	}
	return out.String()
}

// RenderCategory renders a category page: its own text, then its members.
func RenderCategory(c Ctx, w *Wiki, t Title, p *Page, act Action) string {
	var out strings.Builder
	if p != nil {
		out.WriteString(RenderArticle(c, w, p, act))
	} else {
		out.WriteString(md.H1(t.String()))
		out.WriteString(md.Paragraph("_This category has no description page._"))
	}
	members := w.CategoryMembers(t)
	out.WriteString(md.H2(ufmt.Sprintf("Pages in this category (%d)", len(members))))
	if len(members) == 0 {
		out.WriteString(md.Paragraph("_None._"))
		return out.String()
	}
	out.WriteString(titleList(c, members))
	return out.String()
}

// RenderCategories lists every category that has at least one member.
func RenderCategories(c Ctx, w *Wiki) string {
	cats := w.Categories()
	var out strings.Builder
	out.WriteString(md.H1("Categories"))
	if len(cats) == 0 {
		out.WriteString(md.Paragraph("_No categories yet._"))
		return out.String()
	}
	items := []string{}
	for _, t := range cats {
		items = append(items, ufmt.Sprintf("%s (%d)", md.Link(t.Name, c.URL(t)), len(w.CategoryMembers(t))))
	}
	out.WriteString(md.BulletList(items))
	return out.String()
}

// RenderBacklinks renders "what links here" for a title.
func RenderBacklinks(c Ctx, w *Wiki, t Title) string {
	var out strings.Builder
	out.WriteString(md.H1("Pages that link to " + t.String()))
	out.WriteString(md.Paragraph(md.Link("← back to the article", c.URL(t))))
	in := w.Backlinks(t)
	if len(in) == 0 {
		out.WriteString(md.Paragraph("_Nothing links here._"))
		return out.String()
	}
	out.WriteString(titleList(c, in))
	return out.String()
}

// RenderStats renders the wiki's size and what it is paying the chain.
func RenderStats(c Ctx, w *Wiki) string {
	s := w.Stats()
	rows := []string{
		ufmt.Sprintf("pages: %d", s.Pages),
		ufmt.Sprintf("revisions: %d", s.Revisions),
		ufmt.Sprintf("comments: %d", s.Comments),
		ufmt.Sprintf("body bytes on chain: %d", s.BytesHeld),
		ufmt.Sprintf("storage deposit locked by bodies: %s", formatGNOT(s.BytesHeld*DepositPerByte)),
		ufmt.Sprintf("bodies kept per page: %d", s.Retention),
	}
	return md.H1("Wiki stats") + md.BulletList(rows)
}

// RenderTalk renders a page's discussion: top-level messages oldest first,
// each with its replies.
func RenderTalk(c Ctx, w *Wiki, p *Page, offset, count int, act Action) string {
	var out strings.Builder
	out.WriteString(md.H1("Discussion: " + p.Title.String()))

	nav := []string{md.Link("← back to the article", c.URL(p.Title))}
	if act != nil {
		nav = append(nav, md.Link("add a message", act("Comment", "title", p.Title.String(), "replyTo", "0")))
	}
	out.WriteString(md.Paragraph(strings.Join(nav, " · ")))

	threads := w.Comments(p.Title, offset, count)
	if len(threads) == 0 {
		out.WriteString(md.Paragraph("_No messages yet._"))
		return out.String()
	}

	items := []string{}
	for _, th := range threads {
		item := commentLine(c, th.Root, act, p.Title)
		for _, r := range th.Replies {
			item += "\n" + md.Nested(commentLine(c, r, nil, p.Title), "  - ")
		}
		items = append(items, item)
	}
	out.WriteString(md.BulletList(items))

	total := w.NumComments(p.Title)
	if offset+len(threads) < total {
		out.WriteString(md.Paragraph(md.Link("older →",
			c.Sub(p.Title, "talk")+"?offset="+ufmt.Sprintf("%d", offset+count))))
	}
	return out.String()
}

func commentLine(c Ctx, cm *Comment, act Action, t Title) string {
	head := ufmt.Sprintf("**#%d** · %s · %s",
		cm.ID, cm.Time.Format("2006-01-02 15:04"), shortAddr(cm.Author))
	if cm.Hidden {
		return head + "\n\n_This message was removed by a steward._"
	}
	body := sanitize.Block(cm.Body)
	if act != nil {
		body += "\n\n" + md.Link("reply", act("Comment",
			"title", t.String(), "replyTo", ufmt.Sprintf("%d", cm.ID)))
	}
	return head + body
}

func titleList(c Ctx, titles []Title) string {
	items := []string{}
	for _, t := range titles {
		items = append(items, md.Link(t.String(), c.URL(t)))
	}
	return md.BulletList(items)
}

func changeList(c Ctx, changes []*Change) string {
	if len(changes) == 0 {
		return md.Paragraph("_Nothing has happened yet._")
	}
	items := []string{}
	for _, ch := range changes {
		line := ufmt.Sprintf("%s · %s · %s · %s · rev %d",
			md.Link(ch.Title.String(), c.URL(ch.Title)),
			string(ch.Rev.Kind),
			ch.Rev.Time.Format("2006-01-02 15:04"),
			shortAddr(ch.Rev.Author),
			ch.Rev.ID)
		if ch.Rev.Summary != "" {
			line += " · " + sanitize.InlineText(ch.Rev.Summary)
		}
		items = append(items, line)
	}
	return md.BulletList(items)
}

// shortAddr abbreviates an address for display without losing its prefix.
func shortAddr(a address) string {
	s := a.String()
	if len(s) <= 12 {
		return "`" + s + "`"
	}
	return "`" + s[:10] + "…" + s[len(s)-4:] + "`"
}

// formatGNOT renders a ugnot amount as GNOT.
//
// The zero padding is written out by hand: gno's ufmt supports no width or
// padding flags, so ufmt.Sprintf("%06d", 42) returns "42" silently and the
// fractional part of every amount would be wrong by three orders of magnitude.
func formatGNOT(ugnot int) string {
	whole := ugnot / 1000000
	frac := ugnot % 1000000
	s := ufmt.Sprintf("%d", frac)
	for len(s) < 6 {
		s = "0" + s
	}
	s = strings.TrimRight(s, "0")
	if s == "" {
		return ufmt.Sprintf("%d GNOT", whole)
	}
	return ufmt.Sprintf("%d.%s GNOT", whole, s)
}

// plural renders "1 revision" and "2 revisions".
func plural(n int, one, many string) string {
	if n == 1 {
		return ufmt.Sprintf("%d %s", n, one)
	}
	return ufmt.Sprintf("%d %s", n, many)
}
