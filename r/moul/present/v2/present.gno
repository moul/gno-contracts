package present

import (
	"net/url"
	"strconv"
	"strings"
	"time"

	"chain/runtime"

	"gno.land/p/moul/md"
	"gno.land/p/moul/mdtable"
	"gno.land/p/moul/realmpath"
	"gno.land/p/moul/txlink"
	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/avl/v0/pager"
	"gno.land/p/nt/ownable/v0"
	"gno.land/p/nt/seqid/v0"
	"gno.land/p/nt/ufmt/v0"
)

var chainDomain = runtime.ChainDomain()

type Presentation struct {
	id        string
	Slug      string
	Title     string
	Event     string
	Author    string
	Uploader  address
	Date      time.Time
	Content   string
	EditDate  time.Time
	NumSlides int
}

var (
	byID    avl.Tree // id -> *Presentation
	bySlug  avl.Tree // slug -> *Presentation
	idgen   seqid.ID
	Ownable *ownable.Ownable
)

// owner is the realm admin allowed to add/update/delete presentations.
const owner address = "g1manfred47kzduec920z88wfr64ylksmdcedlf5" // @moul

func init() {
	Ownable = ownable.NewWithAddress(owner)
}

// Render handles the realm's rendering logic
func Render(path string) string {
	req := realmpath.Parse(path)

	// Get slug from path
	slug := req.PathPart(0)

	// List view (home)
	if slug == "" {
		return renderList(req)
	}

	// Slides view
	if req.PathPart(1) == "slides" {
		page := 1
		if pageStr := req.Query.Get("page"); pageStr != "" {
			var err error
			page, err = strconv.Atoi(pageStr)
			if err != nil {
				return "400: invalid page number"
			}
		}
		return renderSlides(slug, page)
	}

	// Regular view
	return renderView(slug)
}

// Set adds or updates a presentation
func Set(cur realm, slug, title, event, author, date, content string) string {
	caller := cur.Previous().Address()
	Ownable.AssertOwnedBy(caller)
	return setPresentation(caller, slug, title, event, author, date, content)
}

// setPresentation is the shared record-mutation preamble used by both the
// owner-gated Set entrypoint and the init seeding.
func setPresentation(uploader address, slug, title, event, author, date, content string) string {
	parsedDate, err := time.Parse("2006-01-02", date)
	if err != nil {
		return "400: invalid date format (expected: YYYY-MM-DD)"
	}

	numSlides := 1 // Count intro slide
	for _, line := range strings.Split(content, "\n") {
		if strings.HasPrefix(line, "## ") {
			numSlides++
		}
	}
	numSlides++ // Count thank you slide

	// Reuse the existing id when the slug is already known (update in place).
	var id string
	if v := bySlug.Get(slug); v != nil {
		id = v.(*Presentation).id
	} else {
		id = idgen.Next().String()
	}

	p := &Presentation{
		id:        id,
		Slug:      slug,
		Title:     title,
		Event:     event,
		Author:    author,
		Uploader:  uploader,
		Date:      parsedDate,
		Content:   content,
		EditDate:  time.Now(),
		NumSlides: numSlides,
	}

	byID.Set(id, p)
	bySlug.Set(slug, p)
	return "presentation saved successfully"
}

// Delete removes a presentation
func Delete(cur realm, slug string) string {
	Ownable.AssertOwnedBy(cur.Previous().Address())

	v := bySlug.Get(slug)
	if v == nil {
		return "404: presentation not found"
	}
	p := v.(*Presentation)

	// XXX: consider this:
	// if p.Uploader != cur.Previous().Address() {
	// 	return "401: unauthorized - only the uploader can delete their presentations"
	// }

	byID.Remove(p.id)
	bySlug.Remove(slug)
	return "presentation deleted successfully"
}

func renderList(req *realmpath.Request) string {
	var out strings.Builder
	out.WriteString(md.H1("Presentations"))

	// Setup pager over a tree sorted by the requested field.
	tree := buildSortTree(getSortField(req))
	pgr := pager.NewPager(tree, 10, isSortReversed(req))

	// Get current page. The pager only reads the query string; pass just the
	// query so url.Parse is not tripped by the "/realm:slug" colon in the
	// full realm path.
	page := pgr.MustGetPageByPath("?" + req.Query.Encode())

	// Create table
	dateColumn := renderSortLink(req, "date", "Date")
	titleColumn := renderSortLink(req, "title", "Title")
	authorColumn := renderSortLink(req, "author", "Author")
	table := mdtable.Table{
		Headers: []string{dateColumn, titleColumn, "Event", authorColumn, "Slides"},
	}

	// Add rows from current page
	for _, item := range page.Items {
		p := item.Value.(*Presentation)
		table.Append([]string{
			p.Date.Format("2006-01-02"),
			md.Link(p.Title, localPath(p.Slug, nil)),
			p.Event,
			p.Author,
			ufmt.Sprintf("%d", p.NumSlides),
		})
	}

	out.WriteString(table.String())
	out.WriteString(page.Picker("?" + req.Query.Encode()))
	return out.String()
}

// buildSortTree builds an avl.Tree whose keys order the presentations by the
// requested field. A trailing id keeps keys unique and makes ties
// deterministic (insertion order).
func buildSortTree(field string) *avl.Tree {
	tree := avl.NewTree()
	byID.Iterate("", "", func(id string, v any) bool {
		p := v.(*Presentation)
		var key string
		switch field {
		case "title":
			key = p.Title + "\x00" + id
		case "author":
			key = p.Author + "\x00" + id
		default: // date (and any unknown field)
			key = p.Date.Format("2006-01-02") + "\x00" + id
		}
		tree.Set(key, p)
		return false
	})
	return tree
}

func (p *Presentation) FirstSlide() string {
	var out strings.Builder
	out.WriteString(md.H1(p.Title))
	out.WriteString(md.Paragraph(md.Bold(p.Event) + ", " + p.Date.Format("2 Jan 2006")))
	out.WriteString(md.Paragraph("by " + md.Bold(p.Author))) // XXX: link to u/?
	return out.String()
}

func (p *Presentation) LastSlide() string {
	var out strings.Builder
	out.WriteString(md.H1(p.Title))
	out.WriteString(md.H2("Thank You!"))
	out.WriteString(md.Paragraph(p.Author))
	fullPath := "https://" + chainDomain + localPath(p.Slug, nil)
	out.WriteString(md.Paragraph("🔗 " + md.Link(fullPath, fullPath)))
	// XXX: QRCode
	return out.String()
}

func renderView(slug string) string {
	if slug == "" {
		return "400: missing presentation slug"
	}

	v := bySlug.Get(slug)
	if v == nil {
		return "404: presentation not found"
	}

	p := v.(*Presentation)
	var out strings.Builder

	// Header using FirstSlide helper
	out.WriteString(p.FirstSlide())

	// Slide mode link
	out.WriteString(md.Link("View as slides", localPath(p.Slug+"/slides", nil)) + "\n\n")
	out.WriteString(md.HorizontalRule())
	out.WriteString(md.Paragraph(p.Content))

	// Metadata footer
	out.WriteString(md.HorizontalRule())
	out.WriteString(ufmt.Sprintf("Last edited: %s\n\n", p.EditDate.Format("2006-01-02 15:04:05")))
	out.WriteString(ufmt.Sprintf("Uploader: `%s`\n\n", p.Uploader))
	out.WriteString(ufmt.Sprintf("Number of slides: %d\n\n", p.NumSlides))

	// Admin actions
	// XXX: consider a dynamic toggle for admin actions
	editLink := txlink.Call("Set",
		"slug", p.Slug,
		"title", p.Title,
		"author", p.Author,
		"event", p.Event,
		"date", p.Date.Format("2006-01-02"),
	)
	deleteLink := txlink.Call("Delete", "slug", p.Slug)
	out.WriteString(md.Paragraph(md.Link("Edit", editLink) + " | " + md.Link("Delete", deleteLink)))

	return out.String()
}

// renderSlidesNavigation returns the navigation bar for slides
func renderSlidesNavigation(slug string, currentPage, totalSlides int) string {
	var out strings.Builder
	if currentPage > 1 {
		prevLink := localPath(slug+"/slides", url.Values{"page": {ufmt.Sprintf("%d", currentPage-1)}})
		out.WriteString(md.Link("← Prev", prevLink) + " ")
	}
	out.WriteString(ufmt.Sprintf("| %d/%d |", currentPage, totalSlides))
	if currentPage < totalSlides {
		nextLink := localPath(slug+"/slides", url.Values{"page": {ufmt.Sprintf("%d", currentPage+1)}})
		out.WriteString(" " + md.Link("Next →", nextLink))
	}
	return md.Paragraph(out.String())
}

func renderSlides(slug string, currentPage int) string {
	if slug == "" {
		return "400: missing presentation ID"
	}

	v := bySlug.Get(slug)
	if v == nil {
		return "404: presentation not found"
	}

	p := v.(*Presentation)
	slides := strings.Split("\n"+p.Content, "\n## ")
	if currentPage < 1 || currentPage > p.NumSlides {
		return "404: invalid slide number"
	}

	var out strings.Builder

	// Display current slide
	if currentPage == 1 {
		out.WriteString(p.FirstSlide())
	} else if currentPage == p.NumSlides {
		out.WriteString(p.LastSlide())
	} else {
		out.WriteString(md.H1(p.Title))
		out.WriteString("## " + slides[currentPage-1] + "\n\n")
	}

	out.WriteString(renderSlidesNavigation(slug, currentPage, p.NumSlides))
	return out.String()
}

// Helper functions for sorting and pagination
func getSortField(req *realmpath.Request) string {
	field := req.Query.Get("sort")
	switch field {
	case "date", "author", "title":
		return field
	}
	return "date"
}

func isSortReversed(req *realmpath.Request) bool {
	return req.Query.Get("order") != "asc"
}

func renderSortLink(req *realmpath.Request, field, label string) string {
	currentField := getSortField(req)
	currentOrder := req.Query.Get("order")

	newOrder := "desc"
	if field == currentField && currentOrder != "asc" {
		newOrder = "asc"
	}

	query := req.Query
	query.Set("sort", field)
	query.Set("order", newOrder)

	if field == currentField {
		if newOrder == "asc" {
			label += " ↑"
		} else {
			label += " ↓"
		}
	}

	return md.Link(label, "?"+query.Encode())
}

// helper to create local realm links
func localPath(path string, query url.Values) string {
	req := &realmpath.Request{
		Path:  path,
		Query: query,
	}
	return req.String()
}
