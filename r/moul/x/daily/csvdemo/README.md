# `gno.land/r/moul/x/daily/csvdemo/v0`

Demo of the [`p/moul/x/daily/csv`](/p/moul/x/daily/csv/v0) library: a small
file that breaks every naive splitter, parsed, shown field by field as quoted
literals, written back out, and then the same thing in a semicolon dialect
with comment lines.

The realm holds **no state and no logic of its own**. Every table is computed
from two constants by the library, so the example test that pins `Render`
pins the parser rather than a paragraph somebody typed.

Three things the page is built to show, because they are the three a reader
would otherwise have to take on faith:

- **A quoted field survives a separator and a line break.** The sample's six
  records occupy seven physical lines, and one note holds a comma, a pair of
  doubled quotes and a pipe.
- **What each field actually holds**, rendered with `strconv.Quote`, so an
  embedded newline and a trailing space are visible rather than implied.
- **Where the writer quotes and where it does not**, including the row whose
  bare quote comes back quoted: the round trip is on the records, not on the
  bytes.

Nothing here reads the clock or the chain, so the page is the same on every
call and on every node.

The header row is deliberately shown as record 1. A header is a convention
about the first line, not a feature of the format, and the library does not
invent one.
