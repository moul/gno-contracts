# `gno.land/r/moul/x/daily/jarowinklerdemo/v0`

**Demo of the [`p/moul/x/daily/jarowinkler`](https://github.com/moul/gno-contracts/tree/main/p/moul/x/daily/jarowinkler)
library.** No scoring logic of its own, no state, so `Render` is deterministic.

Two things on the page:

- **Vectors.** The six pairs the record-linkage literature keeps coming back
  to, each one scored under both metrics. `CRATE`/`TRACE` is the row that
  earns its place: it sits under the 0.7 threshold, so the Jaro-Winkler column
  does not move.
- **Inside one score.** `MARTHA` against `MARHTA`, opened up: the window, the
  match and transposition counts, and the rune-by-rune pairing those counts
  came out of. The two rows marked *out of order* are the one swap a reader
  sees, and together they are the single transposition the formula charges.

`Render("/<a>/<b>")` scores whatever you append and shows the same working for
it. Both halves are caller text: the heading fences each one in a code span it
cannot close, and every table cell goes through `ui.Cell`, because a code span
alone does not stop a `|` from opening a column. `escape_test.gno` pins both.
