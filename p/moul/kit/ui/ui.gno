// Package ui is the shared display vocabulary for r/moul realms: the small set
// of rendering decisions that every realm was making on its own, made once.
//
// It deliberately does NOT re-export markdown primitives. Headings, bold,
// lists, code blocks and links already have an owner in
// [p/moul/md](/p/moul/md/v0); import that alongside this package. What lives
// here is only what had no owner and was therefore copy-pasted:
//
//   - Addr: one address shortening for the whole namespace. Eleven realms had
//     their own shortAddr with four different truncation rules, so the same
//     account rendered differently depending on which realm you opened.
//   - Inline / Cell / Excerpt: markdown escaping, delegated to
//     [p/nt/markdown/sanitize](/p/nt/markdown/sanitize/v0). Eight realms
//     hand-rolled a seven-pair strings.NewReplacer that misses most of what
//     the real escaper handles. Excerpt adds the length cap those previews
//     also need, in the order that is safe: cut, then escape.
//   - Action: a clickable call link instead of prose telling the reader to go
//     type a function name.
//   - Table, Empty, Podium: the last recurring scraps.
//
// # Escaping contract
//
// Table cells and Action titles are markdown, not plain text. Anything that
// came from a user must go through [Cell] (inside a table) or [Inline]
// (anywhere else) before it is handed to this package. Output of [Addr],
// [AddrFull] and [Podium] is already safe and must NOT be escaped again.
package ui

import (
	"strings"

	"gno.land/p/moul/helplink/v0"
	"gno.land/p/moul/md/v0"
	"gno.land/p/nt/markdown/sanitize/v0"
)

// Ellipsis is the character placed between the kept head and tail of a
// shortened string.
const Ellipsis = "…"

// Head and Tail are how many characters [Addr] and [Short] keep on each side.
//
// A gno.land address is 40 characters ("g1" plus 38 of bech32 data), so
// 8+1+4 renders it as g1manfre…dlf5: enough of the head to recognise a
// familiar account, enough of the tail to tell two similar ones apart.
const (
	Head = 8
	Tail = 4
)

// minShorten is the length below which shortening cannot save a character:
// Head + len(Ellipsis) + Tail. Strings at or under it are returned unchanged,
// which is why the rule never produces output longer than its input.
const minShorten = Head + 1 + Tail

// Addr renders an address shortened and in backticks: `g1manfre…dlf5`.
//
// This is the default way to show an address. It is monospace (an address is
// opaque data, not prose), and the backticks make it inert markdown, so it is
// safe in a table cell or anywhere else without further escaping.
func Addr(a address) string {
	return md.InlineCode(AddrText(a))
}

// AddrFull renders an address in full, in backticks. Use it where the reader
// needs to copy the value; use [Addr] everywhere else.
func AddrFull(a address) string {
	return md.InlineCode(a.String())
}

// AddrText renders an address shortened, with no backticks. Use it inside a
// link title or another construct where backticks would not render.
func AddrText(a address) string {
	return Short(a.String())
}

// AddrOf is [Addr] for an address already in its string form, which is how
// realms hold one when it is an avl key or a stored field.
func AddrOf(s string) string {
	return md.InlineCode(Short(s))
}

// Short shortens any string with the house rule: unchanged when shortening
// would not save a character, otherwise head + ellipsis + tail.
//
// It is the same rule [Addr] uses, exposed for the non-address strings realms
// also truncate: URLs, handles, commitment hashes.
func Short(s string) string {
	return ShortN(s, Head, Tail)
}

// ShortN is [Short] with an explicit head and tail. A negative head or tail is
// treated as zero. When head+tail cannot save a character against the input,
// the input is returned unchanged.
func ShortN(s string, head, tail int) string {
	if head < 0 {
		head = 0
	}
	if tail < 0 {
		tail = 0
	}
	// Count runes, not bytes: slicing a multi-byte string by byte offset
	// splits a rune and emits replacement characters.
	r := []rune(s)
	if len(r) <= head+1+tail {
		return s
	}
	return string(r[:head]) + Ellipsis + string(r[len(r)-tail:])
}

// Inline escapes user-supplied text for an inline markdown context: a
// sentence, a list item, a link title.
//
// It delegates to sanitize.InlineText, which strips bidi and zero-width
// characters, folds newlines to spaces so the text cannot escape its line,
// and applies the full CommonMark inline escape. Never concatenate
// user-supplied text into rendered output without this.
func Inline(s string) string {
	return sanitize.InlineText(s)
}

// Cell escapes user-supplied text for a markdown table cell: [Inline] plus
// tab and pipe handling, so the value cannot open a new column.
func Cell(s string) string {
	return sanitize.TableCell(s)
}

// Excerpt is [Inline] for a string too long to show whole: it keeps the first
// width runes, appends [Ellipsis], and escapes what it kept.
//
// Use it for a preview of user-written prose where only the beginning carries
// meaning: the first line of a post in an index, a note on a board, a comment
// in a list. For an identifier whose tail has to stay recognisable, an
// address, a hash, a URL, use [Short] instead, which keeps both ends.
//
// The order is the whole point, and it is what a call site gets wrong.
// Escaping inserts backslashes, so cutting an ALREADY-escaped string can
// strand a trailing lone backslash that escapes whatever chrome follows it.
// Excerpt cuts first, on a rune boundary so a multi-byte character is never
// split, then escapes. [Ellipsis] stays outside the escaper: it is this
// package's chrome, not the user's text.
func Excerpt(s string, width int) string {
	if width < 0 {
		width = 0
	}
	r := []rune(s)
	// The same threshold as [ShortN] with no tail: cutting is only worth doing
	// when it saves a character, so a string one rune over is kept whole.
	if len(r) <= width+1 {
		return Inline(s)
	}
	return Inline(string(r[:width])) + Ellipsis
}

// Action renders a clickable call to a function of the current realm.
//
//	ui.Action("Play cell 4", "Move", "gameID", "7", "cell", "4")
//
// Arguments are key/value pairs, as in p/moul/txlink. The title is escaped,
// which is the one thing helplink.Func does not do.
func Action(title, fn string, args ...string) string {
	return helplink.Func(Inline(title), fn, args...)
}

// ActionIn is [Action] against another realm, given as the full package path
// that realm declares on the module line of its gnomod.toml.
//
// This doc deliberately contains no example path, not even a placeholder one.
// gnopm scans doc comments the way it scans imports, so any package path
// spelled out in a comment becomes a dependency of the package holding it: one
// that is neither live nor in the workspace BLOCKS publishing this package and
// everything that imports it, and naming a live one is no better, since it
// drags an unrelated realm into every publish plan. This comment previously
// named a path that deversioning had already removed, which blocked the whole
// ui dependency tree on every chain.
func ActionIn(pkgPath, title, fn string, args ...string) string {
	return helplink.Realm(pkgPath).Func(Inline(title), fn, args...)
}

// Empty renders the placeholder shown where a list would be: an italic line,
// newline-terminated, so it drops into a Render body as-is.
//
//	ui.Empty("No games yet.")  // "_No games yet._\n"
//
// The message is realm chrome, not user input, and is not escaped.
func Empty(msg string) string {
	return md.Italic(msg) + "\n"
}

// Podium returns the medal for a zero-based rank, or "" past third place.
func Podium(rank int) string {
	switch rank {
	case 0:
		return "\U0001F947" // 🥇
	case 1:
		return "\U0001F948" // 🥈
	case 2:
		return "\U0001F949" // 🥉
	default:
		return ""
	}
}

// Table accumulates markdown table rows and renders them.
//
// Cells are markdown, not plain text: pass [Addr] and friends straight
// through, and wrap anything user-supplied in [Cell] first.
//
// Table renders the GFM table itself rather than delegating to
// [p/moul/mdtable](/p/moul/mdtable/v0), which unconditionally rewrites "|" to
// "&#124;" in every cell. Stacked on [Cell], which already emits the GFM
// escape "\|", that double-escapes into a stray backslash ("a\&#124;b"). One
// escaping stage is the only way to get this right, and it has to be the one
// that knows whether the text is user input.
//
//	t := ui.NewTable("#", "X", "O", "Status")
//	t.Row("7", ui.Addr(x), ui.Addr(o), "Turn: X")
//	return t.String()
type Table struct {
	headers []string
	rows    [][]string
}

// NewTable starts a table with the given header cells.
func NewTable(headers ...string) *Table {
	return &Table{headers: headers}
}

// Row appends a row and returns the table, so calls can be chained.
//
// A row with fewer cells than there are headers is padded with empty cells; a
// longer row is kept as-is, which renders as a ragged table rather than
// silently dropping data.
func (t *Table) Row(cells ...string) *Table {
	if n := len(t.headers); len(cells) < n {
		padded := make([]string, n)
		copy(padded, cells)
		cells = padded
	}
	t.rows = append(t.rows, cells)
	return t
}

// Len reports how many rows have been added.
func (t *Table) Len() int { return len(t.rows) }

// String renders the table. A table with no rows renders as "", so a caller
// can fall back to [Empty] with a single check on [Table.Len].
func (t *Table) String() string {
	if len(t.rows) == 0 {
		return ""
	}
	var sb strings.Builder
	sb.WriteString("| " + strings.Join(t.headers, " | ") + " |\n")
	sb.WriteString("|" + strings.Repeat(" --- |", len(t.headers)) + "\n")
	for _, r := range t.rows {
		sb.WriteString("| " + strings.Join(r, " | ") + " |\n")
	}
	return sb.String()
}

// OrEmpty renders the table, or the placeholder when it has no rows.
func (t *Table) OrEmpty(msg string) string {
	if len(t.rows) == 0 {
		return Empty(msg)
	}
	return t.String()
}

// Join concatenates parts, skipping empty ones, with sep between them. It is
// the small piece of glue every Render needs to assemble optional sections
// without emitting stray separators.
func Join(sep string, parts ...string) string {
	kept := make([]string, 0, len(parts))
	for _, p := range parts {
		if p != "" {
			kept = append(kept, p)
		}
	}
	return strings.Join(kept, sep)
}
