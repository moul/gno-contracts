package blog

import (
	"strconv"
	"strings"

	"gno.land/p/moul/kit/ui/v0"
)

// linkPrefix is what a permalink starts with. gnoweb addresses a realm's
// render path with ':' after the package path, so this is realmPath with the
// leading "gno.land" dropped and the separator appended.
const linkPrefix = "/r/moul/blog:"

// defaultIntro is the header shown before SetIntro has ever been called, i.e.
// right after the first deploy or after a redeploy wiped the state.
const defaultIntro = "# moul's blog\n\nNotes on gno.land, from the person building on it.\n"

// Render serves three views:
//
//	""         the index, newest first
//	"<slug>"   one post
//	"t/<tag>"  every post carrying a tag
func Render(path string) string {
	path = strings.TrimSpace(path)
	switch {
	case path == "":
		return renderIndex()
	case strings.HasPrefix(path, "t/"):
		return renderTag(strings.TrimPrefix(path, "t/"))
	default:
		return renderPost(path)
	}
}

func header() string {
	if intro == "" {
		return defaultIntro
	}
	return strings.TrimRight(intro, "\n") + "\n"
}

func renderIndex() string {
	var b strings.Builder
	b.WriteString(header())

	if posts.Size() == 0 {
		b.WriteString("\n")
		b.WriteString(ui.Empty("Nothing published yet."))
		return b.String()
	}

	// order is keyed by "<date>/<slug>", so walking it backwards is
	// newest-first without a sort the language does not have.
	order.ReverseIterate("", "", func(_ string, value any) bool {
		b.WriteString("\n")
		b.WriteString(entry(value.(*post)))
		return false
	})
	return b.String()
}

func renderTag(tag string) string {
	tag = strings.ToLower(strings.TrimSpace(tag))

	var b strings.Builder
	b.WriteString("# Tagged ")
	b.WriteString(ui.Inline(tag))
	b.WriteString("\n")

	found := 0
	order.ReverseIterate("", "", func(_ string, value any) bool {
		p := value.(*post)
		if !hasTag(p, tag) {
			return false
		}
		found++
		b.WriteString("\n")
		b.WriteString(entry(p))
		return false
	})
	if found == 0 {
		b.WriteString("\n")
		b.WriteString(ui.Empty("No post carries this tag."))
	}
	b.WriteString("\n[← all posts](" + linkPrefix + ")\n")
	return b.String()
}

func renderPost(slug string) string {
	v := posts.Get(slug)
	if v == nil {
		return "# Not found\n\nNo post at " + strconv.Quote(ui.Inline(slug)) +
			".\n\n[← all posts](" + linkPrefix + ")\n"
	}
	p := v.(*post)

	var b strings.Builder
	b.WriteString("# ")
	b.WriteString(ui.Inline(p.title))
	b.WriteString("\n\n")
	b.WriteString(byline(p))
	b.WriteString("\n\n")
	// The body is markdown written by `author`, who is also the only address
	// that can call Set. It is the post, so it renders verbatim: escaping it
	// would turn every heading and link in it into literal text.
	b.WriteString(strings.TrimRight(p.body, "\n"))
	b.WriteString("\n\n---\n\n[← all posts](" + linkPrefix + ")\n")
	return b.String()
}

// entry is one row of a listing: linked title, byline, excerpt.
func entry(p *post) string {
	var b strings.Builder
	b.WriteString("## [")
	b.WriteString(ui.Inline(p.title))
	b.WriteString("](")
	b.WriteString(linkPrefix)
	b.WriteString(p.slug)
	b.WriteString(")\n\n")
	b.WriteString(byline(p))
	b.WriteString("\n\n")
	b.WriteString(ui.Excerpt(firstLine(p.body), excerptLen))
	b.WriteString("\n")
	return b.String()
}

// byline is the date plus the post's tags as links, on one line.
func byline(p *post) string {
	var b strings.Builder
	b.WriteString(p.date)
	for _, t := range splitTags(p.tags) {
		b.WriteString(" · [#")
		b.WriteString(ui.Inline(t))
		b.WriteString("](")
		b.WriteString(linkPrefix)
		b.WriteString("t/")
		b.WriteString(t)
		b.WriteString(")")
	}
	return b.String()
}

func hasTag(p *post, tag string) bool {
	for _, t := range splitTags(p.tags) {
		if t == tag {
			return true
		}
	}
	return false
}

// firstLine returns the first non-empty, non-heading line of a body, which is
// what an excerpt should show: a post that opens with "## Something" would
// otherwise preview its own heading.
func firstLine(body string) string {
	for _, line := range strings.Split(body, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		return line
	}
	return ""
}
