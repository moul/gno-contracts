package gallery

import "strings"

// doc builds the plain-text target: a document that reads well as-is, rather
// than markdown with the syntax characters deleted.
//
// This is a prototype, deliberately small and deliberately here rather than in
// a p/ package. Porting one realm is not enough to know what the shared
// document model should be; porting the fifth will be. What it already pins is
// the set of rules that make text good instead of merely stripped:
//
//  1. A link prints its text inline and collects the URL into a numbered
//     footnote. Never "[text](url)", which is the single worst thing markdown
//     does to a terminal reader.
//  2. A heading is underlined, not prefixed with '#'.
//  3. Art is emitted verbatim: never wrapped, never escaped, never fenced.
//  4. Prose is wrapped at a fixed width; art and fields are not.
type doc struct {
	b     strings.Builder
	links []string
}

// width is where prose wraps. 72 leaves room for a quoting prefix in an email
// or a diff without re-wrapping.
const width = 72

func (d *doc) H1(s string) {
	d.blank()
	d.b.WriteString(s + "\n" + strings.Repeat("=", runeLen(s)) + "\n")
}

func (d *doc) H2(s string) {
	d.blank()
	d.b.WriteString(s + "\n" + strings.Repeat("-", runeLen(s)) + "\n")
}

func (d *doc) Para(s string) {
	if s == "" {
		return
	}
	d.blank()
	d.b.WriteString(wrap(s, width) + "\n")
}

func (d *doc) Item(s string) {
	d.b.WriteString("  - " + s + "\n")
}

// Table writes columns padded to their widest cell, under a rule. An unpadded
// pipe table is the other thing markdown does to a terminal reader that no
// amount of character-stripping fixes: the columns stop lining up and the table
// stops being a table.
//
// Cells are laid out by rune count, not byte count, so a box-drawing glyph or
// an accent does not shift the column.
func (d *doc) Table(headers []string, rows [][]string) {
	if len(headers) == 0 {
		return
	}
	w := make([]int, len(headers))
	for i, h := range headers {
		w[i] = runeLen(h)
	}
	for _, r := range rows {
		for i, c := range r {
			if i < len(w) && runeLen(c) > w[i] {
				w[i] = runeLen(c)
			}
		}
	}

	d.blank()
	d.b.WriteString("  " + joinPadded(headers, w) + "\n")

	rule := make([]string, len(headers))
	for i := range rule {
		rule[i] = strings.Repeat("-", w[i])
	}
	d.b.WriteString("  " + joinPadded(rule, w) + "\n")

	for _, r := range rows {
		d.b.WriteString("  " + joinPadded(r, w) + "\n")
	}
}

// joinPadded pads every cell but the last, which would only add trailing space.
func joinPadded(cells []string, w []int) string {
	var b strings.Builder
	for i, c := range cells {
		if i > 0 {
			b.WriteString("  ")
		}
		b.WriteString(c)
		if i < len(cells)-1 && i < len(w) {
			b.WriteString(strings.Repeat(" ", w[i]-runeLen(c)))
		}
	}
	return b.String()
}

func (d *doc) Field(k, v string) {
	d.b.WriteString("  " + k + ": " + v + "\n")
}

// Art writes a block verbatim. No fence, no indent, no escaping: a consumer
// that asked for text asked for the picture as it is.
func (d *doc) Art(s string) {
	d.blank()
	d.b.WriteString(s + "\n")
}

// Link prints the text inline and defers the URL to the footnote block.
func (d *doc) Link(text, url string) {
	d.links = append(d.links, url)
	d.b.WriteString("  " + text + " [" + itoa(len(d.links)) + "]\n")
}

func (d *doc) String() string {
	out := d.b.String()
	if len(d.links) == 0 {
		return out
	}
	var b strings.Builder
	b.WriteString(out)
	b.WriteString("\nLinks:\n")
	for i, u := range d.links {
		b.WriteString("  [" + itoa(i+1) + "] " + u + "\n")
	}
	return b.String()
}

// blank writes a separating newline unless the document is empty or already
// ends in one, so no block has to know what came before it.
func (d *doc) blank() {
	s := d.b.String()
	if s == "" || strings.HasSuffix(s, "\n\n") {
		return
	}
	d.b.WriteString("\n")
}

// wrap breaks on spaces at w runes. A word longer than w is left alone rather
// than cut: a URL or a realm path is worse broken than wide.
func wrap(s string, w int) string {
	var out strings.Builder
	line := 0
	for i, word := range strings.Fields(s) {
		n := runeLen(word)
		switch {
		case i == 0:
			out.WriteString(word)
			line = n
		case line+1+n > w:
			out.WriteString("\n" + word)
			line = n
		default:
			out.WriteString(" " + word)
			line += 1 + n
		}
	}
	return out.String()
}

func runeLen(s string) int {
	n := 0
	for range s {
		n++
	}
	return n
}
