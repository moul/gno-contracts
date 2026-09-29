// Package gallery is a curated index of art on gno.land, in whichever form the
// reader can actually consume.
//
// It stores no art. Every piece lives in somebody else's realm; this one
// renders the ones it can import and points at the ones it cannot.
//
// # The target is a parameter
//
// Every page answers to ?fmt=txt as well as the default markdown. The text
// target is not markdown with the characters deleted: links become numbered
// footnotes, headings get underlines instead of a leading '#', and art is
// emitted verbatim rather than fenced. The result is meant to be piped, or read
// by anything that is not a browser.
//
// ?fmt=ansi is deliberately absent. Colour cannot reach gnoweb, so a realm that
// offered it would be handing every web reader a page of escape bytes. Terminal
// colour is p/moul/art's Canvas.ANSI, for a consumer that asked for it over
// something other than gnoweb.
package gallery

import (
	"strings"

	"gno.land/p/moul/art/v0"
	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/moul/realmpath/v0"
)

func Render(path string) string {
	req := realmpath.Parse(path)
	text := req.Query.Get("fmt") == "txt"

	if slug := strings.TrimPrefix(req.Path, "piece/"); slug != req.Path && slug != "" {
		return renderPiece(slug, text)
	}
	return renderIndex(text)
}

// banner is drawn with p/moul/art rather than typed as a string literal,
// because a gallery that hand-writes its own ASCII would be a poor advert for
// the library it exists to show.
func banner() string {
	c := art.NewCanvas(22, 2)
	c.Write(0, 0, "moul's gallery")
	c.Write(0, 1, "art on gno.land")
	return c.Frame("", art.Round).Text()
}

func renderIndex(text bool) string {
	live, linked := 0, 0
	for _, p := range catalog() {
		if p.Live() {
			live++
		} else {
			linked++
		}
	}

	if text {
		var d doc
		d.Art(banner())
		d.Para("Art on gno.land, rendered rather than described. Nothing here is stored in this realm: every piece lives where its author put it.")
		rows := [][]string{}
		for _, p := range catalog() {
			shown := "linked"
			if p.Live() {
				shown = "rendered here"
			}
			rows = append(rows, []string{p.Slug, p.Author, p.Origin, shown})
		}
		d.Table([]string{"Piece", "Author", "Where", "Shown"}, rows)
		d.Para(plural(live, "piece") + " rendered from source, " + plural(linked, "piece") + " linked.")
		d.Para("Open one at /r/moul/gallery:piece/<slug>, with ?fmt=txt for this form.")
		return d.String()
	}

	out := md.H1("moul's gallery")
	out += md.CodeBlock(banner())
	out += "\n"
	out += "Art on gno.land, rendered rather than described. Nothing here is stored in this realm: every piece lives where its author put it.\n\n"

	t := ui.NewTable("Piece", "Author", "Where", "Shown")
	for _, p := range catalog() {
		shown := "linked"
		if p.Live() {
			shown = "rendered here"
		}
		t.Row(
			md.Link(p.Title, "/r/moul/gallery:piece/"+p.Slug),
			ui.Inline(p.Author),
			md.InlineCode(p.Origin),
			shown,
		)
	}
	out += t.OrEmpty("nothing indexed yet")
	out += "\n" + md.Italic(plural(live, "piece")+" rendered from source, "+plural(linked, "piece")+" linked.") + "\n\n"
	out += md.Italic("Every page here also answers to `?fmt=txt`.") + "\n"
	return out
}

func renderPiece(slug string, text bool) string {
	p, ok := find(slug)
	if !ok {
		if text {
			return "No piece called " + slug + ".\n"
		}
		return md.H1("Not found") + ui.Empty("no piece called "+ui.Inline(slug))
	}

	if text {
		var d doc
		d.H1(p.Title)
		if p.Live() {
			d.Art(p.Draw())
		} else {
			d.Para("Not rendered here: this realm cannot import the source.")
		}
		d.Para(p.Note)
		d.Field("Author", p.Author)
		d.Field("License", p.License)
		d.Field("Source", p.Origin)
		d.Link("the source realm", "https://gno.land/"+p.Origin)
		return d.String()
	}

	out := md.H1(p.Title)
	if p.Live() {
		out += md.CodeBlock(p.Draw())
	} else {
		out += ui.Empty("not rendered here: this realm cannot import the source") + "\n"
	}
	out += "\n" + ui.Inline(p.Note) + "\n\n"

	t := ui.NewTable("Field", "Value")
	t.Row("Author", ui.Cell(p.Author))
	t.Row("License", ui.Cell(p.License))
	t.Row("Source", md.Link(p.Origin, "/"+p.Origin))
	out += t.String()

	out += "\n" + md.Link("< the gallery", "/r/moul/gallery") + "\n"
	return out
}

func plural(n int, word string) string {
	s := itoa(n) + " " + word
	if n != 1 {
		s += "s"
	}
	return s
}

func itoa(v int) string {
	if v == 0 {
		return "0"
	}
	var buf [20]byte
	i := len(buf)
	for v > 0 {
		i--
		buf[i] = byte('0' + v%10)
		v /= 10
	}
	return string(buf[i:])
}
