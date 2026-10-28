// Package csvdemo is a small gnoweb demo of the csv parser provided by the
// [p/moul/x/daily/csv](/p/moul/x/daily/csv/v0) library: the quoting rules,
// a sample file that breaks every naive splitter, the round trip, the
// dialects, and what a bad field says.
//
// It holds no state and no logic of its own. Every table on the page is
// computed from the constants below by the library under test, so the
// example test that pins this output is pinning the parser rather than a
// paragraph somebody typed.
package csvdemo

import (
	"strconv"
	"strings"

	"gno.land/p/moul/kit/ui/v0"
	"gno.land/p/moul/x/daily/csv/v0"
)

// sample is the worked example, and every line of it is chosen to be a
// counter-example to splitting on newlines and then on commas: a separator
// inside quotes, a line break inside quotes, a doubled quote, a bare quote,
// an empty field, and a pipe, which is the character a markdown table would
// lose if the page built its tables by hand.
const sample = `name,note,qty
alice,"said ""hi"", then left",2
bob,"two
lines",1
carol,,0
dave,a|b,3
erin,5" nails,12`

// dialectSample is the same data in the shape a European spreadsheet exports
// it: semicolon separated, with a comment line on top.
const dialectSample = `# exported 2026-03-10
name;note;qty
alice;"a;b";2
bob;plain;1`

// Render renders the demo for gnoweb.
//
//	Render("") / Render("/") -> the full demo
func Render(path string) string {
	var b strings.Builder

	b.WriteString("# CSV\n\n")
	b.WriteString("Comma-separated values with the quoting rules, which is ")
	b.WriteString("the half every hand-rolled splitter leaves out. Demoing ")
	b.WriteString("the [`p/moul/x/daily/csv`](/p/moul/x/daily/csv/v0) ")
	b.WriteString("library.\n\n")

	b.WriteString("## The file\n\n")
	b.WriteString("```\n" + sample + "\n```\n\n")
	b.WriteString("Six records. A reader that splits on newlines sees ")
	b.WriteString("seven lines, and a reader that then splits on commas ")
	b.WriteString("disagrees with itself about how many columns there ")
	b.WriteString("are.\n\n")

	b.WriteString("## Parsed\n\n")
	records, err := csv.Parse(sample)
	if err != nil {
		b.WriteString(ui.Inline(err.Error()) + "\n\n")
		return b.String()
	}
	pt := ui.NewTable("#", "name", "note", "qty")
	for i, rec := range records {
		pt.Row(
			strconv.Itoa(i+1),
			ui.Cell(field(rec, 0)),
			ui.Cell(field(rec, 1)),
			ui.Cell(field(rec, 2)),
		)
	}
	b.WriteString(pt.String() + "\n")
	b.WriteString("Record 2 holds a comma and a pair of quotes, record 3 ")
	b.WriteString("holds a line break, record 5 holds a pipe, and record 6 ")
	b.WriteString("holds a quote that opens nothing. Each one survives as ")
	b.WriteString("content: the escaping happens once, on the way into the ")
	b.WriteString("markdown cell, and never on the way into the parser.\n\n")
	b.WriteString("The header is record 1 and nothing else. A header is a ")
	b.WriteString("convention about the first line, not a feature of the ")
	b.WriteString("format, so the parser does not invent one: a realm that ")
	b.WriteString("wants column names takes `records[0]` and says so.\n\n")

	b.WriteString("## What each field actually holds\n\n")
	b.WriteString("Same records, one row per field, rendered as a quoted ")
	b.WriteString("literal so a line break and a trailing space are ")
	b.WriteString("visible rather than implied.\n\n")
	lt := ui.NewTable("record", "field", "literal", "bytes")
	for i, rec := range records {
		for j, f := range rec {
			lt.Row(
				strconv.Itoa(i+1),
				strconv.Itoa(j+1),
				"`"+strconv.Quote(f)+"`",
				strconv.Itoa(len(f)),
			)
		}
	}
	b.WriteString(lt.String() + "\n")

	b.WriteString("## Written back out\n\n")
	b.WriteString("```\n" + csv.Format(records) + "```\n\n")
	b.WriteString("Quoted where it has to be, which is not always where ")
	b.WriteString("the input had it: `erin`'s bare quote comes back as a ")
	b.WriteString("quoted field. **The round trip is on the records, not ")
	b.WriteString("on the bytes.** A writer that emitted that quote bare ")
	b.WriteString("would be leaning on the same forgiveness this reader ")
	b.WriteString("extends, and no other reader owes it.\n\n")
	b.WriteString("Two of the quoting decisions are positional rather ")
	b.WriteString("than about the content, and neither can be made by ")
	b.WriteString("looking at the field alone: a record holding one empty ")
	b.WriteString("field is written `\"\"` because a blank line is not a ")
	b.WriteString("record, and a first field starting with the comment ")
	b.WriteString("byte is quoted because the reader would otherwise drop ")
	b.WriteString("the line and the record with it.\n\n")

	b.WriteString("## Quoting, field by field\n\n")
	qt := ui.NewTable("field", "needs quoting", "written as", "why")
	for _, c := range []struct {
		f   string
		why string
	}{
		{"plain", "nothing to escape"},
		{"", "an empty field is not an ambiguous one"},
		{" padded ", "nothing is trimmed, so nothing needs protecting"},
		{"a,b", "holds the separator"},
		{`a"b`, "holds a quote"},
		{"a\nb", "holds a line break"},
	} {
		yes := "no"
		if csv.NeedsQuoting(c.f, ',') {
			yes = "yes"
		}
		qt.Row(
			"`"+strconv.Quote(c.f)+"`",
			yes,
			"`"+strconv.Quote(csv.Field(c.f, ','))+"`",
			c.why,
		)
	}
	b.WriteString(qt.String() + "\n")
	b.WriteString("A quote inside an unquoted field is a literal ")
	b.WriteString("character, which is why `5\" nails` parses rather than ")
	b.WriteString("failing. A quote that *opens* a field quotes it, and ")
	b.WriteString("text after the closing quote is an error, because ")
	b.WriteString("nothing can be read into it.\n\n")

	b.WriteString("## A different dialect\n\n")
	b.WriteString("```\n" + dialectSample + "\n```\n\n")
	d := csv.Dialect{Comma: ';', Comment: '#'}
	drecs, err := csv.ParseDialect(dialectSample, d)
	if err != nil {
		b.WriteString(ui.Inline(err.Error()) + "\n\n")
		return b.String()
	}
	dt := ui.NewTable("#", "field 1", "field 2", "field 3")
	for i, rec := range drecs {
		dt.Row(
			strconv.Itoa(i+1),
			ui.Cell(field(rec, 0)),
			ui.Cell(field(rec, 1)),
			ui.Cell(field(rec, 2)),
		)
	}
	b.WriteString(dt.String() + "\n")
	b.WriteString("The comment line is not a record. It is only a comment ")
	b.WriteString("at the start of a line, so a `#` inside a field and a ")
	b.WriteString("`#` inside quotes are both content.\n\n")

	b.WriteString("## What a bad field says\n\n")
	et := ui.NewTable("input", "error")
	for _, bad := range []string{
		`a,"b`,
		`"a"b`,
		`"a" ,b`,
		"a,b\nc,\"d\ne,f",
	} {
		msg := "accepted"
		if _, err := csv.Parse(bad); err != nil {
			msg = err.Error()
		}
		et.Row("`"+strconv.Quote(bad)+"`", ui.Cell(msg))
	}
	b.WriteString(et.String() + "\n")
	b.WriteString("The record and the field are both counted from one and ")
	b.WriteString("both named. On a file where every line looks like the ")
	b.WriteString("last, the position is the entire answer.\n\n")

	b.WriteString("## Why a realm would want this\n\n")
	b.WriteString("Because csv is what a human already has. A roster, an ")
	b.WriteString("airdrop list, a price table: it comes out of a ")
	b.WriteString("spreadsheet as csv, and the realm that accepts it as ")
	b.WriteString("one argument is the realm that does not ask anybody to ")
	b.WriteString("reformat anything. The failure this package prevents is ")
	b.WriteString("not a crash. A splitter gets the first few rows right ")
	b.WriteString("and loses a field the first time somebody writes a ")
	b.WriteString("comma inside a note, on chain, permanently.\n")

	return b.String()
}

// field returns one field of a record, or an empty string past its end, so a
// ragged record does not have to be special-cased at every call site.
func field(rec []string, i int) string {
	if i >= len(rec) {
		return ""
	}
	return rec[i]
}
