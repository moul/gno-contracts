package threads

import (
	"strconv"
	"strings"

	"chain/runtime"

	"gno.land/p/moul/kit/store/v0"
	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/realmpath/v0"
	th "gno.land/p/moul/x/social/threads/v0"
)

// Render routes three views: the realm's own index, one page's threads, and
// one thread.
//
// A page key contains slashes, so "page/<key>" is split on the prefix rather
// than by path element: realmpath gives the parts, and rejoining them would
// only be a way to get it wrong.
// perPage bounds every list this realm renders. A Render is paid for by every
// reader, so its cost has to be bounded by what it SHOWS rather than by what
// anybody has ever written, and both Post and Reply are permissionless with no
// delete path. 20 matches what the index already shows with board.Recent(20).
const perPage = 20

func Render(path string) string {
	req := realmpath.Parse(path)

	switch {
	case strings.HasPrefix(req.Path, "page/"):
		return renderPage(strings.TrimPrefix(req.Path, "page/"))
	case strings.HasPrefix(req.Path, "thread/"):
		return renderThread(strings.TrimPrefix(req.Path, "thread/"))
	case req.Path == "":
		return renderIndex()
	default:
		return md.H1("Not found") + "No such view: " + ui.Inline(req.Path)
	}
}

func renderIndex() string {
	out := md.H1("Threads")
	out += "A discussion block any realm can embed, keyed on the page it appears on.\n\n"

	t := ui.NewTable("threads", "pages", "THREAD supply")
	t.Row(strconv.Itoa(board.Len()), strconv.Itoa(board.Pages()), strconv.FormatInt(points.Supply(), 10))
	out += t.String()

	out += md.H2("Recent, across every page")
	out += listing(board.Recent(20), true)

	out += md.H2("The token")
	out += points.Render()

	out += md.H2("Embedding it")
	out += "Two lines in the host realm, and it stores nothing:\n\n"
	out += md.LanguageCodeBlock("go", `import "`+realmPath+`"

func Render(path string) string {
	return body + threads.RenderBlock()
}`)
	out += "The page key is the host realm's own path, read off the call. " +
		md.InlineCode("RenderBlockFor(page)") + " names one explicitly.\n"

	return out
}

func renderPage(page string) string {
	if !th.ValidPage(page) {
		return md.H1("Threads") + "Not a page key: " + ui.Inline(page)
	}
	out := md.H1("Threads on " + ui.Inline(page))
	out += md.Link("the page itself", th.RealmURL(page)) + "\n\n"

	// Finding 325-cost-at-caps-1: this passed limit 0, which means "every
	// thread anybody ever posted on this page". Post is permissionless and
	// the page key is any string, so a visitor fills a page they do not own
	// and every reader of it pays. There is no delete path, so it is
	// irreversible.
	total := board.PageLen(page)
	out += listing(board.List(page, runtime.ChainHeight(), perPage), false)
	if total > perPage {
		out += md.Italic("Showing " + strconv.Itoa(perPage) + " of " +
			strconv.Itoa(total) + " threads, newest and pinned first.") + "\n"
	}

	out += "\n" + ui.Action("💬 Post here", "Post", "page", page, "body", "") + "\n"
	return out
}

func renderThread(raw string) string {
	id, ok := store.ParseID(raw)
	if !ok {
		return md.H1("Threads") + "Not a thread id: " + ui.Inline(raw)
	}
	t, found := board.Get(id)
	if !found {
		return md.H1("Threads") + "No thread #" + id.String()
	}

	out := md.H1("Thread #" + id.String())
	out += md.Blockquote(ui.Inline(t.Body)) + "\n"
	out += md.Italic("by "+ui.Addr(t.Author)+" · on "+
		md.Link(t.Page, th.PageURL(realmPath, t.Page))+
		" · "+strconv.Itoa(t.Repliers())+" earned") + "\n\n"

	if t.PinnedUntil > runtime.ChainHeight() {
		out += "📌 pinned until block " + strconv.FormatInt(t.PinnedUntil, 10) + "\n\n"
	}

	out += md.H2("Replies")
	if len(t.Replies) == 0 {
		out += ui.Empty("Nobody has replied yet.")
	} else {
		// Finding 325-cost-at-caps-1: this rendered every reply ever
		// written. Reply is permissionless and nothing deletes one, so the
		// page a reader pays for grows without a bound anybody controls.
		// The newest are shown, because that is what a reader of a thread
		// came for.
		shown := t.Replies
		if len(shown) > perPage {
			shown = shown[len(shown)-perPage:]
		}
		r := ui.NewTable("by", "said", "block")
		for _, rep := range shown {
			r.Row(ui.Addr(rep.Author), ui.Cell(rep.Body), strconv.FormatInt(rep.At, 10))
		}
		out += r.String()
		if len(t.Replies) > perPage {
			out += md.Italic("Showing the newest " + strconv.Itoa(perPage) + " of " +
				strconv.Itoa(len(t.Replies)) + " replies.") + "\n"
		}
	}

	out += "\n" + ui.Action("💬 Reply", "Reply", "threadID", id.String(), "body", "") +
		" · " + ui.Action("📌 Boost", "Boost", "threadID", id.String()) + "\n"
	return out
}

// listing renders a set of threads. withPage adds the page column, which the
// index needs and a page view would only repeat.
func listing(items []th.Listing, withPage bool) string {
	if len(items) == 0 {
		return ui.Empty("No threads yet.")
	}
	headers := []string{"", "#", "thread", "by", "replies"}
	if withPage {
		headers = append(headers, "page")
	}
	t := ui.NewTable(headers...)
	now := runtime.ChainHeight()
	for _, it := range items {
		mark := ""
		if it.Thread.Pinned(now) {
			mark = "📌"
		}
		cells := []string{
			mark,
			// The link title is the id, never the body: md.Link escapes
			// markdown but not a pipe, and a pipe in a table cell opens a
			// column. ui.Cell is the only thing that rewrites it.
			md.Link("#"+it.ID.String(), th.ThreadURL(realmPath, it.ID)),
			ui.Cell(ui.ShortN(it.Thread.Body, th.ExcerptLen, 0)),
			ui.Addr(it.Thread.Author),
			strconv.Itoa(len(it.Thread.Replies)),
		}
		if withPage {
			cells = append(cells, ui.Cell(it.Thread.Page))
		}
		t.Row(cells...)
	}
	return t.String()
}
