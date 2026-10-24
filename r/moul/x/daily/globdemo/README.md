# `gno.land/r/moul/x/daily/globdemo/v0`

**A gnoweb demo of [`p/moul/x/daily/glob`](/p/moul/x/daily/glob/v0)**: the
pattern grammar, the two matching modes, and the allowlist the library exists
for.

`Render("")` is the whole realm. It holds no state and takes no transaction, so
the page is a pure function of the fixed tables at the top of `globdemo.gno`
and every verdict in it is computed by the library rather than written down.
That is what lets an example test pin the output byte for byte: a change in the
matcher shows up as a diff in `render_example_test.gno`, not as prose that
quietly stopped being true.

Five sections, and the third is the point:

1. **The grammar**, one row per token, each with a pattern and a subject that
   exercises it.
2. **The two modes**, the same pattern run through `Match` and `MatchPath`.
   Two of the five rows disagree, which is the whole difference between them.
3. **The allowlist**, two rules against six candidate paths, with a
   `strings.HasPrefix` column beside the `AnyPath` one. The last two rows are
   paths the prefix check lets through and the matcher does not.
4. **Valid**, three well-formed patterns and three typos, showing that a
   malformed pattern is inert rather than permissive.
5. **Why the matcher is a loop**, the pattern that makes a recursive glob
   exponential, matched here in linear-by-quadratic time.

The wrong implementation (`naivePrefix`) is kept in the source on purpose, so
the page can show it being wrong instead of asserting that it is.
