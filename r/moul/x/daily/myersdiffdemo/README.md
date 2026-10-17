# `gno.land/r/moul/x/daily/myersdiffdemo/v0`

**A gnoweb demo of the [`p/moul/x/daily/myersdiff`](/p/moul/x/daily/myersdiff/v0)
library**: four fixed document pairs, each rendered as a unified diff, each
picked to show one property of the algorithm rather than to look impressive.

It holds no diff logic of its own and no state. Every diff line and every count
on the page is computed by the library at render time, so a change in the
algorithm shows up as a diff in `ExampleRender` rather than as prose nobody
re-reads.

The four scenarios, and why each one is there:

- **`patch`.** The ordinary case: most of the file untouched. This is the
  shape Myers is fast at, and the reason the cost is `O((n+m)*d)` rather than
  `O(n*m)`.
- **`insert`.** Appending to an empty document, so the left side contributes no
  lines at all and the header has to say `-0,0`. That convention is the one
  hand-written hunk headers get wrong.
- **`move`.** Four lines reordered. The algorithm compares sequences, so the
  answer is a delete and an insert, never a move: the page shows the cost of
  that choice instead of claiming it does not exist.
- **`starved`.** Two unrelated documents with the budget set to 2, which is too
  small for the real answer. The page reports `minimal: no` and still reports
  that replaying the script reproduces the right-hand document, which is the
  property that survives the budget.

Append a number to widen the context: `/patch/0` prints the changed lines alone
and `/patch/6` prints the whole file as one hunk. Out-of-range values are
clamped to 0..6, and anything that is not a number leaves the default.

**No caller string reaches the page.** The first path segment is matched against
the scenario table by exact equality and an unknown one renders the index; the
second is parsed as an integer and clamped. That is why this realm carries an
`untrusted-render` opt-out comment rather than an escaper: there is nothing to
escape, and `TestNoCallerEchoOnThePage` feeds it a link, an image, a gnoweb tag,
a backtick and a newline to keep it that way.

Rendering is deterministic and costs no chain reads, so the page is the same on
every node and at every height.
