package wiki

import (
	"strings"

	"gno.land/p/nt/markdown/sanitize/v0"
)

// Link is one wikilink occurrence in a body.
type Link struct {
	Target   string // target text as written, before ParseTitle
	Label    string // display text; "" means render the target
	Explicit bool   // written [[:Category:X]]: link to the category, do not join it
	Start    int    // byte offset of the opening delimiter
	End      int    // byte offset just past the closing delimiter
}

// ScanLinks finds every [[target|label]] occurrence delimited by open and
// close.
//
// The delimiters are parameters because the same syntax has to be found twice
// with different bytes. Indexing reads the raw body, where a link is
// "[[X]]". Rendering reads the body after sanitize.BlockRich, where the very
// same link is "\[\[X\]\]" because the sanitizer escapes every "[". Rendering
// must sanitize first and rewrite second: a rewriter that ran first would
// hand the markdown links it just generated to the escaper, and every link on
// the wiki would render as literal text.
//
// A link whose inner text spans a newline or is empty is not a link. When a
// nearer opener appears inside the inner text, scanning restarts from it, so
// "[[a [[b]]" yields b rather than a mis-parsed a.
func ScanLinks(s, openTok, closeTok string) []Link {
	out := []Link{}
	i := 0
	for i < len(s) {
		a := strings.Index(s[i:], openTok)
		if a < 0 {
			break
		}
		a += i
		rest := a + len(openTok)
		b := strings.Index(s[rest:], closeTok)
		if b < 0 {
			break
		}
		b += rest

		inner := s[rest:b]
		if n := strings.Index(inner, openTok); n >= 0 {
			i = rest + n
			continue
		}
		i = b + len(closeTok)
		if inner == "" || strings.Contains(inner, "\n") {
			continue
		}

		l := Link{Start: a, End: i}
		if p := strings.Index(inner, "|"); p >= 0 {
			l.Target = strings.TrimSpace(inner[:p])
			l.Label = strings.TrimSpace(inner[p+1:])
		} else {
			l.Target = strings.TrimSpace(inner)
		}
		if strings.HasPrefix(l.Target, ":") {
			l.Explicit = true
			l.Target = strings.TrimSpace(l.Target[1:])
		}
		if l.Target == "" {
			continue
		}
		out = append(out, l)
	}
	return out
}

// redirectTarget returns the canonical title a body redirects to, or "".
// The syntax is MediaWiki's: "#REDIRECT [[Target]]" on the first line.
func redirectTarget(body string) string {
	line := body
	if i := strings.Index(line, "\n"); i >= 0 {
		line = line[:i]
	}
	line = strings.TrimSpace(line)
	if len(line) < len("#REDIRECT") || !strings.EqualFold(line[:len("#REDIRECT")], "#REDIRECT") {
		return ""
	}
	links := ScanLinks(line, "[[", "]]")
	if len(links) == 0 {
		return ""
	}
	t, err := ParseTitle(links[0].Target)
	if err != nil {
		return ""
	}
	return t.String()
}

// Ctx carries what rendering needs from the realm: where the realm lives, and
// which titles exist. Its function fields are read during a single Render call
// and never stored, so no closure is ever persisted.
type Ctx struct {
	Base   string            // realm path prefix, e.g. "/r/moul/x/wiki/v0"
	Exists func(Title) bool // nil treats every title as existing
}

func (c Ctx) exists(t Title) bool {
	if c.Exists == nil {
		return true
	}
	return c.Exists(t)
}

// URL is the render path of a title under this realm.
func (c Ctx) URL(t Title) string { return c.Sub(t, "") }

// Sub is the render path of a sub-route of a title, e.g. "history".
func (c Ctx) Sub(t Title, route string) string {
	u := c.Base + ":" + t.Slug()
	if route != "" {
		u += "/" + route
	}
	return escapeURL(u)
}

// SpecialURL is the render path of a Special: page.
func (c Ctx) SpecialURL(name, query string) string {
	u := c.Base + ":Special:" + name
	if query != "" {
		u += "?" + query
	}
	return escapeURL(u)
}

// escapeURL percent-encodes the characters a title may contain that would
// otherwise terminate a markdown link destination or split a path. Titles
// admit "(", ")", " ", "'" and "," (see validTitleRune), and an unencoded ")"
// ends the "(...)" of a markdown link at the first occurrence, which turns
// [[Mercury (planet)]] into a broken link plus stray text.
func escapeURL(u string) string {
	r := strings.NewReplacer(
		" ", "%20",
		"(", "%28",
		")", "%29",
		"'", "%27",
		",", "%2C",
	)
	return sanitize.URL(r.Replace(u))
}

// RewriteLinks turns the wikilinks of an already-sanitized body into markdown
// links. Category declarations are removed from the flow: membership is shown
// by the rendered footer, not inline, which is also what MediaWiki does.
//
// s MUST be the output of sanitize.BlockRich or sanitize.Block, and open/close
// MUST be the escaped delimiters. Passing a raw body here would emit links
// built from unsanitized bytes.
func RewriteLinks(c Ctx, s string) string {
	links := ScanLinks(s, `\[\[`, `\]\]`)
	if len(links) == 0 {
		return s
	}
	var out strings.Builder
	prev := 0
	for _, l := range links {
		out.WriteString(s[prev:l.Start])
		prev = l.End

		t, err := ParseTitle(unescapeInline(l.Target))
		if err != nil {
			// Not a usable title: leave the sanitized text in place. It is
			// already escaped, so it renders as the literal brackets the
			// author typed.
			out.WriteString(s[l.Start:l.End])
			continue
		}
		if t.NS == NSCategory && !l.Explicit {
			continue
		}
		label := l.Label
		if label == "" {
			label = t.String()
		}
		if c.exists(t) {
			out.WriteString("[" + label + "](" + c.URL(t) + ")")
		} else {
			// A red link: the page does not exist yet. Point at the same
			// path, which renders the "create this page" stub.
			out.WriteString("[" + label + "](" + c.URL(t) + ") ⁺")
		}
	}
	out.WriteString(s[prev:])
	return out.String()
}

// unescapeInline undoes the backslash escaping the sanitizer applies inside a
// link's inner text, so ParseTitle sees the title the author typed.
func unescapeInline(s string) string {
	if !strings.Contains(s, `\`) {
		return s
	}
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		if s[i] == '\\' && i+1 < len(s) {
			i++
		}
		b.WriteByte(s[i])
	}
	return b.String()
}
