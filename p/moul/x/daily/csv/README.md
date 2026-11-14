# `gno.land/p/moul/x/daily/csv/v0`

**Comma-separated values with the quoting rules**: `Parse`, `ParseDialect`, `Format`, `FormatDialect`, `Field`, `NeedsQuoting`, `Dialect`.

```go
import "gno.land/p/moul/x/daily/csv/v0"

records, err := csv.Parse(input)             // [][]string, RFC 4180 quoting
text := csv.Format(records)                  // back out, quoted only where needed

d := csv.Dialect{Comma: ';', Comment: '#', Strict: true}
records, err = csv.ParseDialect(input, d)
```

The quoting rules are the half every hand-rolled splitter leaves out, and
leaving them out does not fail loudly. A field wrapped in double quotes may
contain the separator and may contain a line break:

```
name,note,qty
alice,"said ""hi"", then left",2
bob,"two
lines",1
```

Split that on newlines and then on commas and you get four records of the
wrong shape instead of three of the right one. The result is still a
rectangle of strings, which is exactly why nobody notices until a note
contains a comma, on chain, permanently.

**The API is a string in, a string out.** No reader, no writer, no streaming:
a realm has no stream. Its input arrived whole in a transaction and its
output is a page.

## What this package decides

RFC 4180 is four paragraphs long and silent on most of what a parser actually
meets, so these are choices rather than readings. Each one is pinned by a
test.

- **A quote that opens a field quotes it; a quote anywhere else in an
  unquoted field is a literal character.** So `5" nails` parses as the eight
  bytes you would expect, where Go's `encoding/csv` rejects it. Text *after*
  a closing quote is an error, because there is nothing it could be read
  into.
- **A blank line is not a record**, and a trailing newline does not make an
  empty one. A line holding a single quoted empty field *is* a record, which
  is why `Format` writes one that way rather than emitting a line the reader
  would skip.
- **Line breaks are LF or CRLF. A lone CR is content**, never a terminator. A
  CRLF inside a quoted field is kept verbatim rather than folded to LF, which
  is the other divergence from Go and the one that makes
  `Parse(Format(x))` return `x` for every `x`.
- **Nothing is trimmed, ever.** A leading space is content and survives the
  round trip unquoted. `NeedsQuoting` says no to `" padded "` on purpose:
  quoting it would only help a reader that trims, and this is not that
  reader.
- **Records may be ragged.** `Dialect.Strict` is how you ask for the other
  answer, and it names the record that disagreed and both counts.

## The round trip is on the records, not on the bytes

`Parse(Format(records))` returns `records`. `Format(Parse(text))` does **not**
always return `text`, and the difference is deliberate: a bare quote comes
back as a quoted field, because a writer that emitted it bare would be leaning
on the forgiveness this reader extends and that no other reader owes it.

Two of the writer's quoting decisions are positional, which is why `Field`
alone cannot make them and `FormatDialect` has to:

- a record holding exactly one empty field is written `""`, not as an empty
  line
- the first field of a record is quoted when it starts with the dialect's
  comment byte

Both exist for the same reason: the alternative output parses cleanly and
comes back one record short.

## Errors name the position

`csv: record 2, field 2: unterminated quoted field`. Records and fields are
counted from one. On a file where every line looks like the last, the
position is the entire answer, and an unterminated quote is reported where it
*opened* rather than where the input ran out.

`FormatDialect` returns no error. An invalid dialect falls back to the
defaults, because a writer that silently refused to write would be worse than
one that wrote valid csv in the wrong dialect.

Live demo: [`r/moul/x/daily/csvdemo`](/r/moul/x/daily/csvdemo/v0).
