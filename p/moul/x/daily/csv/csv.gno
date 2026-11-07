// Package csv reads and writes comma-separated values the way RFC 4180
// describes them, which is to say: with the quoting rules, and therefore
// without the bug every hand-rolled splitter has.
//
// The bug is always the same one. A field wrapped in double quotes may
// contain the separator, and may contain a line break:
//
//	name,note
//	alice,"said ""hi"", then left"
//	bob,"two
//	lines"
//
// Splitting that on newlines and then on commas produces four records of the
// wrong shape instead of three records of the right one, and it produces them
// silently: the result is still a rectangle of strings. That is the whole
// reason to import a parser rather than write six lines.
//
// The API is a string in, a string out. There is no reader and no writer,
// because a realm has no stream: its input arrived whole in a transaction and
// its output is a page.
//
//	records, err := csv.Parse(input)
//	text := csv.Format(records)
//
// [Dialect] covers the three things real files vary in, a different
// separator, comment lines, and a fixed field count, and [ParseDialect] and
// [FormatDialect] take one. Everything else is fixed on purpose.
//
// # What this package decides
//
// RFC 4180 is four paragraphs long and silent on most of what a parser meets,
// so these are choices, and each one is pinned by a test:
//
//   - A quote that opens a field quotes it. A quote anywhere else in an
//     unquoted field is a literal character, so a,"b and a"b both parse.
//     Text after a closing quote is an error, because nothing can be read
//     into it.
//   - A blank line is not a record, and a trailing newline does not make an
//     empty one. A line holding a single quoted empty field is a record,
//     which is why [Format] writes one that way.
//   - Line breaks are LF or CRLF. A lone CR is content, never a terminator.
//     A CRLF inside a quoted field is kept verbatim rather than folded to LF,
//     so Parse(Format(x)) returns x for every x.
//   - Nothing is trimmed, ever. A leading space is content, and a field that
//     was written with one comes back with one.
//   - Records may be ragged. Dialect.Strict is how you ask for the other
//     answer, and it names the record that disagreed.
//
// Live demo: r/moul/x/daily/csvdemo.
package csv

import (
	"errors"
	"strconv"
	"strings"
)

// quote is the field delimiter RFC 4180 fixes. It is not configurable: every
// escaping rule in the format is written in terms of it, and a dialect that
// changed it would not be csv any more.
const quote = byte('"')

// Dialect carries the three things real csv files actually vary in. The zero
// value is RFC 4180 with a comma, which is what [Parse] and [Format] use.
type Dialect struct {
	// Comma is the field separator. Zero means ','. It may not be a quote, a
	// line feed or a carriage return.
	Comma byte

	// Comment, when non-zero, makes a line whose first byte is Comment a
	// comment: the whole line is skipped and it is not a record. It is only
	// examined at the start of a line, so a separator inside a field and a
	// byte inside a quoted field are never comments. It may not equal Comma
	// or the quote.
	Comment byte

	// Strict rejects a record holding a different number of fields from the
	// first one. RFC 4180 requires the equal count; most files in the world
	// do not have it, so it is opt-in.
	Strict bool

	// CRLF makes [FormatDialect] terminate records with "\r\n" rather than
	// "\n". The parser accepts both whatever this says.
	CRLF bool
}

// resolve fills in the defaults and refuses a dialect that cannot be parsed
// unambiguously. It is called by the entry points rather than by Dialect's
// construction because Dialect is a plain struct a caller fills in by hand.
func (d Dialect) resolve() (comma, comment byte, err error) {
	comma = d.Comma
	if comma == 0 {
		comma = ','
	}
	switch comma {
	case quote, '\n', '\r':
		return 0, 0, errors.New("csv: " + describe(comma) + " cannot be the separator")
	}
	comment = d.Comment
	switch comment {
	case 0:
		// no comment character, which is the default
	case comma:
		return 0, 0, errors.New("csv: the comment byte and the separator are both " + describe(comma))
	case quote:
		return 0, 0, errors.New("csv: " + describe(comment) + " cannot be the comment byte")
	}
	return comma, comment, nil
}

// Parse reads records in the default dialect: comma separated, RFC 4180
// quoting, no comments, ragged records allowed.
func Parse(s string) ([][]string, error) {
	return ParseDialect(s, Dialect{})
}

// ParseDialect reads records in the given dialect.
//
// Every record is a fresh slice and nothing is shared with the input, so the
// result is safe to store. An error names the record and the field it came
// from, both counted from one: a parse error with no coordinates is useless
// on a file where every line looks like the last.
func ParseDialect(s string, d Dialect) ([][]string, error) {
	comma, comment, err := d.resolve()
	if err != nil {
		return nil, err
	}

	records := [][]string{}
	i, n := 0, len(s)
	for i < n {
		switch {
		case comment != 0 && s[i] == comment:
			i = skipLine(s, i)
			continue
		case s[i] == '\n':
			i++ // a blank line is not a record
			continue
		case s[i] == '\r' && i+1 < n && s[i+1] == '\n':
			i += 2
			continue
		}
		rec, next, err := parseRecord(s, i, comma, len(records)+1)
		if err != nil {
			return nil, err
		}
		records = append(records, rec)
		i = next
	}

	if d.Strict && len(records) > 1 {
		want := len(records[0])
		for i, rec := range records[1:] {
			if len(rec) != want {
				return nil, errors.New("csv: record " + strconv.Itoa(i+2) +
					": has " + strconv.Itoa(len(rec)) + " fields, want " + strconv.Itoa(want))
			}
		}
	}
	return records, nil
}

// skipLine returns the index just past the next line break, or the end.
func skipLine(s string, i int) int {
	for ; i < len(s); i++ {
		if s[i] == '\n' {
			return i + 1
		}
	}
	return len(s)
}

// parseRecord reads one record starting at i, which the caller has already
// established is neither a blank line nor a comment.
func parseRecord(s string, i int, comma byte, recNo int) ([]string, int, error) {
	rec := []string{}
	n := len(s)
	for {
		fieldNo := len(rec) + 1

		var f string
		if i < n && s[i] == quote {
			var err error
			f, i, err = parseQuoted(s, i, recNo, fieldNo)
			if err != nil {
				return nil, 0, err
			}
			// Only a quoted field can end somewhere a separator or a line
			// break is not: an unquoted one stops at nothing else.
			if i < n && s[i] != comma && s[i] != '\n' && !crlfAt(s, i) {
				return nil, 0, errors.New("csv: record " + strconv.Itoa(recNo) +
					", field " + strconv.Itoa(fieldNo) + ": " + describe(s[i]) +
					" after closing quote")
			}
		} else {
			f, i = parseBare(s, i, comma)
		}
		rec = append(rec, f)

		switch {
		case i >= n:
			return rec, i, nil
		case s[i] == comma:
			i++
		case crlfAt(s, i):
			return rec, i + 2, nil
		default: // s[i] == '\n'
			return rec, i + 1, nil
		}
	}
}

// crlfAt reports whether a CRLF pair starts at i.
func crlfAt(s string, i int) bool {
	return i+1 < len(s) && s[i] == '\r' && s[i+1] == '\n'
}

// parseQuoted reads a field that opens with a quote, starting at that quote.
// A doubled quote inside is one literal quote; the first single one ends the
// field.
func parseQuoted(s string, i, recNo, fieldNo int) (string, int, error) {
	var b strings.Builder
	n := len(s)
	for i++; i < n; i++ {
		if s[i] != quote {
			b.WriteByte(s[i])
			continue
		}
		if i+1 < n && s[i+1] == quote {
			b.WriteByte(quote)
			i++
			continue
		}
		return b.String(), i + 1, nil
	}
	return "", 0, errors.New("csv: record " + strconv.Itoa(recNo) +
		", field " + strconv.Itoa(fieldNo) + ": unterminated quoted field")
}

// parseBare reads a field that did not open with a quote. It ends at the
// separator, at a line feed, or at the end of the input, and a carriage
// return is dropped only when it is the one in a CRLF.
func parseBare(s string, i int, comma byte) (string, int) {
	start := i
	for ; i < len(s); i++ {
		if s[i] == comma || s[i] == '\n' {
			break
		}
	}
	end := i
	if end > start && s[end-1] == '\r' && i < len(s) && s[i] == '\n' {
		end--
	}
	return s[start:end], i
}

// Format writes records in the default dialect, each terminated by a line
// feed, quoting a field exactly when it has to.
func Format(records [][]string) string {
	return FormatDialect(records, Dialect{})
}

// FormatDialect writes records in the given dialect.
//
// Two of the quoting decisions here are positional and therefore cannot be
// made by [Field] alone, and both of them exist so that parsing the output
// returns the input:
//
//   - A record holding exactly one empty field is written as "" rather than
//     as an empty line, which the parser would skip.
//   - The first field of a record is quoted when it starts with the
//     dialect's comment byte, which the parser would otherwise read as a
//     comment and drop with it the whole record.
//
// An invalid dialect falls back to the defaults rather than panicking: this
// returns no error, and a writer that silently refused to write would be
// worse than one that wrote valid csv in the wrong dialect.
func FormatDialect(records [][]string, d Dialect) string {
	comma, comment, err := d.resolve()
	if err != nil {
		comma, comment = ',', 0
	}
	eol := "\n"
	if d.CRLF {
		eol = "\r\n"
	}

	var b strings.Builder
	for _, rec := range records {
		for i, f := range rec {
			if i > 0 {
				b.WriteByte(comma)
			}
			switch {
			case len(rec) == 1 && f == "":
				b.WriteString(`""`)
			case i == 0 && comment != 0 && len(f) > 0 && f[0] == comment:
				b.WriteString(enclose(f))
			default:
				b.WriteString(Field(f, comma))
			}
		}
		b.WriteString(eol)
	}
	return b.String()
}

// Field renders one field, quoting it only when the content requires it. It
// is the half of the writer a caller needs when assembling a line by hand;
// [FormatDialect] is the half that knows where the field sits.
func Field(f string, comma byte) string {
	if comma == 0 {
		comma = ','
	}
	if !NeedsQuoting(f, comma) {
		return f
	}
	return enclose(f)
}

// enclose wraps a field in quotes and doubles the quotes inside it.
func enclose(f string) string {
	var b strings.Builder
	b.WriteByte(quote)
	for i := 0; i < len(f); i++ {
		if f[i] == quote {
			b.WriteByte(quote)
		}
		b.WriteByte(f[i])
	}
	b.WriteByte(quote)
	return b.String()
}

// NeedsQuoting reports whether a field cannot be written as it stands: it
// holds the separator, a quote, or a line break.
//
// Leading and trailing spaces are deliberately not a reason. Nothing in this
// package trims, so a space survives the round trip unquoted; quoting it
// would only be for the benefit of a reader that does trim, and that reader
// is not this one.
func NeedsQuoting(f string, comma byte) bool {
	if comma == 0 {
		comma = ','
	}
	for i := 0; i < len(f); i++ {
		switch f[i] {
		case comma, quote, '\n', '\r':
			return true
		}
	}
	return false
}

// describe names a byte the way an error message should: readable for the
// ones a human typed, numeric for the ones they cannot see.
func describe(b byte) string {
	switch b {
	case '\n':
		return "a line feed"
	case '\r':
		return "a carriage return"
	case '\t':
		return "a tab"
	case ' ':
		return "a space"
	}
	if b < 0x20 || b >= 0x7f {
		return "byte " + strconv.Itoa(int(b))
	}
	return strconv.Quote(string([]byte{b}))
}
