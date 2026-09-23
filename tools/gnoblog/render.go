package main

import (
	"sort"
	"strings"
)

// The local preview mirrors r/moul/blog/render.gno: same order, same headings,
// same links, so a post can be read in its final shape before a transaction
// exists.
//
// One thing it does NOT mirror, on purpose: the realm escapes titles, tags and
// excerpts through p/moul/kit/ui before emitting them, which inserts
// backslashes that a markdown renderer then removes again. Reproducing that
// here would make the preview harder to read to no end, since the rendered
// result is identical. What it does reproduce exactly is the ORDER, which is
// the part that is easy to get wrong and impossible to see in the files.

const linkPrefix = "/r/moul/blog:"

const defaultIntro = "# moul's blog\n\nNotes on gno.land, from the person building on it.\n"

// preview renders the index. Passing a slug renders that post instead.
func preview(posts []postFile, slug string) string {
	if slug != "" {
		for _, p := range posts {
			if p.slug == slug {
				return previewPost(p)
			}
		}
		return "# Not found\n\nNo local post at " + slug + ".\n"
	}
	return previewIndex(posts)
}

func previewIndex(posts []postFile) string {
	var b strings.Builder
	b.WriteString(introOf(posts))

	for _, p := range newestFirst(posts) {
		b.WriteString("\n## [")
		b.WriteString(p.title)
		b.WriteString("](")
		b.WriteString(linkPrefix)
		b.WriteString(p.slug)
		b.WriteString(")\n\n")
		b.WriteString(byline(p))
		b.WriteString("\n\n")
		b.WriteString(excerpt(firstLine(p.body), 200))
		b.WriteString("\n")
	}
	return b.String()
}

func previewPost(p postFile) string {
	return "# " + p.title + "\n\n" + byline(p) + "\n\n" +
		strings.TrimRight(p.body, "\n") +
		"\n\n---\n\n[← all posts](" + linkPrefix + ")\n"
}

func introOf(posts []postFile) string {
	for _, p := range posts {
		if p.isIntro() && p.body != "" {
			return strings.TrimRight(p.body, "\n") + "\n"
		}
	}
	return defaultIntro
}

// newestFirst orders posts the way the realm's `order` tree does: by
// "<date>/<slug>", descending. The date is YYYY-MM-DD precisely so that this
// is a string comparison on both sides.
func newestFirst(posts []postFile) []postFile {
	out := make([]postFile, 0, len(posts))
	for _, p := range posts {
		if !p.isIntro() {
			out = append(out, p)
		}
	}
	sort.Slice(out, func(i, j int) bool {
		a := out[i].date + "/" + out[i].slug
		b := out[j].date + "/" + out[j].slug
		return a > b
	})
	return out
}

func byline(p postFile) string {
	var b strings.Builder
	b.WriteString(p.date)
	for _, t := range strings.Split(p.tags, ",") {
		if t == "" {
			continue
		}
		b.WriteString(" · [#" + t + "](" + linkPrefix + "t/" + t + ")")
	}
	return b.String()
}

// firstLine mirrors the realm: the first non-empty, non-heading line, because
// a post opening with a heading would otherwise preview its own title.
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

// excerpt mirrors ui.Excerpt's cut: first `width` runes, then the ellipsis,
// and a string one rune over is kept whole rather than losing a character to
// gain one.
func excerpt(s string, width int) string {
	r := []rune(s)
	if len(r) <= width+1 {
		return s
	}
	return string(r[:width]) + "…"
}
