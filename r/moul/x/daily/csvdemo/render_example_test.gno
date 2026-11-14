package csvdemo

// ExampleRender pins the realm Render output as a testable example.
//
// The block below is copied verbatim from what gno printed, never hand
// typed: every cell in it is produced by the library under test, so a
// change in the parser shows up here as a diff rather than as prose.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # CSV
	//
	// Comma-separated values with the quoting rules, which is the half every hand-rolled splitter leaves out. Demoing the [`p/moul/x/daily/csv`](/p/moul/x/daily/csv/v0) library.
	//
	// ## The file
	//
	// ```
	// name,note,qty
	// alice,"said ""hi"", then left",2
	// bob,"two
	// lines",1
	// carol,,0
	// dave,a|b,3
	// erin,5" nails,12
	// ```
	//
	// Six records. A reader that splits on newlines sees seven lines, and a reader that then splits on commas disagrees with itself about how many columns there are.
	//
	// ## Parsed
	//
	// | # | name | note | qty |
	// | --- | --- | --- | --- |
	// | 1 | name | note | qty |
	// | 2 | alice | said "hi", then left | 2 |
	// | 3 | bob | two lines | 1 |
	// | 4 | carol |  | 0 |
	// | 5 | dave | a\|b | 3 |
	// | 6 | erin | 5" nails | 12 |
	//
	// Record 2 holds a comma and a pair of quotes, record 3 holds a line break, record 5 holds a pipe, and record 6 holds a quote that opens nothing. Each one survives as content: the escaping happens once, on the way into the markdown cell, and never on the way into the parser.
	//
	// The header is record 1 and nothing else. A header is a convention about the first line, not a feature of the format, so the parser does not invent one: a realm that wants column names takes `records[0]` and says so.
	//
	// ## What each field actually holds
	//
	// Same records, one row per field, rendered as a quoted literal so a line break and a trailing space are visible rather than implied.
	//
	// | record | field | literal | bytes |
	// | --- | --- | --- | --- |
	// | 1 | 1 | `"name"` | 4 |
	// | 1 | 2 | `"note"` | 4 |
	// | 1 | 3 | `"qty"` | 3 |
	// | 2 | 1 | `"alice"` | 5 |
	// | 2 | 2 | `"said \"hi\", then left"` | 20 |
	// | 2 | 3 | `"2"` | 1 |
	// | 3 | 1 | `"bob"` | 3 |
	// | 3 | 2 | `"two\nlines"` | 9 |
	// | 3 | 3 | `"1"` | 1 |
	// | 4 | 1 | `"carol"` | 5 |
	// | 4 | 2 | `""` | 0 |
	// | 4 | 3 | `"0"` | 1 |
	// | 5 | 1 | `"dave"` | 4 |
	// | 5 | 2 | `"a|b"` | 3 |
	// | 5 | 3 | `"3"` | 1 |
	// | 6 | 1 | `"erin"` | 4 |
	// | 6 | 2 | `"5\" nails"` | 8 |
	// | 6 | 3 | `"12"` | 2 |
	//
	// ## Written back out
	//
	// ```
	// name,note,qty
	// alice,"said ""hi"", then left",2
	// bob,"two
	// lines",1
	// carol,,0
	// dave,a|b,3
	// erin,"5"" nails",12
	// ```
	//
	// Quoted where it has to be, which is not always where the input had it: `erin`'s bare quote comes back as a quoted field. **The round trip is on the records, not on the bytes.** A writer that emitted that quote bare would be leaning on the same forgiveness this reader extends, and no other reader owes it.
	//
	// Two of the quoting decisions are positional rather than about the content, and neither can be made by looking at the field alone: a record holding one empty field is written `""` because a blank line is not a record, and a first field starting with the comment byte is quoted because the reader would otherwise drop the line and the record with it.
	//
	// ## Quoting, field by field
	//
	// | field | needs quoting | written as | why |
	// | --- | --- | --- | --- |
	// | `"plain"` | no | `"plain"` | nothing to escape |
	// | `""` | no | `""` | an empty field is not an ambiguous one |
	// | `" padded "` | no | `" padded "` | nothing is trimmed, so nothing needs protecting |
	// | `"a,b"` | yes | `"\"a,b\""` | holds the separator |
	// | `"a\"b"` | yes | `"\"a\"\"b\""` | holds a quote |
	// | `"a\nb"` | yes | `"\"a\nb\""` | holds a line break |
	//
	// A quote inside an unquoted field is a literal character, which is why `5" nails` parses rather than failing. A quote that *opens* a field quotes it, and text after the closing quote is an error, because nothing can be read into it.
	//
	// ## A different dialect
	//
	// ```
	// # exported 2026-03-10
	// name;note;qty
	// alice;"a;b";2
	// bob;plain;1
	// ```
	//
	// | # | field 1 | field 2 | field 3 |
	// | --- | --- | --- | --- |
	// | 1 | name | note | qty |
	// | 2 | alice | a;b | 2 |
	// | 3 | bob | plain | 1 |
	//
	// The comment line is not a record. It is only a comment at the start of a line, so a `#` inside a field and a `#` inside quotes are both content.
	//
	// ## What a bad field says
	//
	// | input | error |
	// | --- | --- |
	// | `"a,\"b"` | csv: record 1, field 2: unterminated quoted field |
	// | `"\"a\"b"` | csv: record 1, field 1: "b" after closing quote |
	// | `"\"a\" ,b"` | csv: record 1, field 1: a space after closing quote |
	// | `"a,b\nc,\"d\ne,f"` | csv: record 2, field 2: unterminated quoted field |
	//
	// The record and the field are both counted from one and both named. On a file where every line looks like the last, the position is the entire answer.
	//
	// ## Why a realm would want this
	//
	// Because csv is what a human already has. A roster, an airdrop list, a price table: it comes out of a spreadsheet as csv, and the realm that accepts it as one argument is the realm that does not ask anybody to reformat anything. The failure this package prevents is not a crash. A splitter gets the first few rows right and loses a field the first time somebody writes a comma inside a note, on chain, permanently.
}
