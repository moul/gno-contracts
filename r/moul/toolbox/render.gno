package toolbox

import (
	"net/url"
	"strings"

	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/realmpath/v0"
	tb "gno.land/p/moul/toolbox/v0"
)

// Render routes gnoweb paths:
//
//	/                 the directory
//	/?tag=identity    the directory, filtered to one tag
//	/<slug>           one tool
func Render(path string) string {
	req := realmpath.Parse(path)
	parts := req.PathParts()

	if len(parts) == 0 || parts[0] == "" {
		return renderIndex(req.Query.Get("tag"))
	}
	if len(parts) > 1 {
		return renderUnknown(parts[0] + "/" + parts[1])
	}
	t, ok := catalog.Get(parts[0])
	if !ok {
		return renderUnknown(parts[0])
	}
	return renderTool(t)
}

func renderIndex(tag string) string {
	var b strings.Builder
	b.WriteString(md.H1("Toolbox"))
	b.WriteString("\nSmall utilities on gno.land. Each one is its own realm, composing contracts that are already on chain and showing the answer as a page instead of as a query you have to compose.\n")

	list := catalog.List()
	if tag != "" {
		list = catalog.ByTag(tag)
		b.WriteString("\nFiltered to " + md.InlineCode(tag) + ". " +
			md.Link("Show all", hubURL) + "\n")
	}
	b.WriteString("\n" + tb.Index(list))

	if tag == "" {
		if links := tagLinks(catalog, hubURL); links != "" {
			b.WriteString("\nTags: " + links + "\n")
		}
	}

	b.WriteString("\n" + md.H2("What a tool is"))
	b.WriteString("\n" + md.BulletList([]string{
		"A realm at " + md.InlineCode("gno.land/r/moul/toolbox/<slug>") + ", reachable on its own.",
		"Read-only unless it says otherwise: a page you open, not a transaction you sign.",
		"Composed from contracts already on chain, so the toolbox adds the view and not the data.",
	}))
	return b.String()
}

// tagLinks renders the tag filter row, or "" when nothing is tagged.
//
// QueryEscape, not plain concatenation: a tag is an arbitrary string on Tool,
// and "a&b" would otherwise become a second query parameter while "a#b" would
// become a fragment, in both cases linking to a filter nobody asked for.
func tagLinks(c *tb.Catalog, base string) string {
	tags := c.Tags()
	if len(tags) == 0 {
		return ""
	}
	links := make([]string, 0, len(tags))
	for _, name := range tags {
		links = append(links, md.Link(name, base+"?tag="+url.QueryEscape(name)))
	}
	return strings.Join(links, " · ")
}

func renderTool(t tb.Tool) string {
	var b strings.Builder
	b.WriteString(tb.Nav(hubURL, "Toolbox"))
	b.WriteString("\n" + tb.Card(t))
	return b.String()
}

func renderUnknown(slug string) string {
	var b strings.Builder
	b.WriteString(md.H1("Not found"))
	b.WriteString("\nNo tool called " + md.InlineCode(slug) + ".\n")
	b.WriteString("\n" + md.Link("Back to the toolbox", hubURL) + "\n")
	return b.String()
}
