package kitindexdemo

import (
	"strconv"

	"gno.land/p/moul/kit/store/v0"
	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/realmpath/v0"
)

// Render is the whole public surface. Three pages: the tag list, one tag, one
// author.
//
// Every row goes through ui.NewTable rather than concatenated pipes, and every
// caller string through ui.Cell, because a public path is immutable and a
// Render that ships wrong ships forever.
func Render(path string) string {
	req := realmpath.Parse(path)
	switch req.PathPart(0) {
	case "":
		return renderIndex(req)
	case "tag":
		return renderTag(req.PathPart(1))
	case "author":
		return renderAuthor(req.PathPart(1))
	default:
		return md.H1("Not found") + ui.Empty("No such page.")
	}
}

func renderIndex(req *realmpath.Request) string {
	// The page number is user input: clamp it into 1..pages, or ?page=-1
	// renders an empty board under a footer saying "page -1 of 2".
	pages := byTag.Pages(PageSize)
	page := 1
	if n, err := strconv.Atoi(req.Query.Get("page")); err == nil {
		page = n
	}
	if page < 1 {
		page = 1
	}
	if page > pages {
		page = pages
	}

	t := ui.NewTable("tag", "notes")
	for _, e := range byTag.Page(page, PageSize) {
		t.Row(
			md.Link(e.Key, "./kitindexdemo:tag/"+e.Key),
			strconv.Itoa(len(e.IDs)),
		)
	}

	return ui.Join("\n",
		md.H1("Notes by tag"),
		md.Paragraph(strconv.Itoa(notes.Len())+" note(s) under "+
			strconv.Itoa(byTag.Keys())+" tag(s), by "+
			strconv.Itoa(byAuthor.Keys())+" author(s)."),
		t.OrEmpty("Nothing posted yet."),
		pager(page, pages),
		md.Paragraph(ui.Action("Post a note", "Post", "tag", "", "body", "")),
	)
}

func renderTag(tag string) string {
	if tag == "" {
		return md.H1("Not found") + ui.Empty("No tag given.")
	}
	return md.H1("#"+ui.Cell(tag)) + notesTable(byTag.Lookup(tag), "No notes under this tag.")
}

func renderAuthor(addr string) string {
	if addr == "" {
		return md.H1("Not found") + ui.Empty("No author given.")
	}
	return md.H1("Notes by "+ui.AddrOf(addr)) +
		notesTable(byAuthor.Lookup(addr), "This address has posted nothing.")
}

// notesTable renders a set of ids as rows, skipping any id the store no longer
// holds.
//
// Skipping rather than panicking: an index and a store are two containers, and
// a reader should see the records that exist rather than a page that aborts.
// Retract keeps the two in step, so a miss here means a bug worth surviving,
// not worth hiding.
func notesTable(hits []store.ID, empty string) string {
	t := ui.NewTable("#", "author", "tag", "note", "height")
	for _, id := range hits {
		v, ok := notes.Get(id)
		if !ok {
			continue
		}
		n := v.(*note)
		t.Row(
			id.String(),
			ui.Addr(n.Author),
			md.InlineCode(n.Tag),
			ui.Cell(n.Body),
			strconv.FormatInt(n.Height, 10),
		)
	}
	return t.OrEmpty(empty)
}

// pager renders the previous/next links, or nothing when there is one page.
func pager(page, pages int) string {
	if pages < 2 {
		return ""
	}
	out := ""
	if page > 1 {
		out += md.Link("previous", "./kitindexdemo:?page="+strconv.Itoa(page-1)) + " "
	}
	out += "page " + strconv.Itoa(page) + " of " + strconv.Itoa(pages)
	if page < pages {
		out += " " + md.Link("next", "./kitindexdemo:?page="+strconv.Itoa(page+1))
	}
	return out
}
