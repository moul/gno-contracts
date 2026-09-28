# `gno.land/p/moul/x/daily/fenwick/v0`

**A Binary Indexed Tree over `int64`**: `New`, `FromSlice`, `Add`, `Set`, `Prefix`, `Range`, `At`, `Total`, `SearchPrefix`, `Slice`, `Covers`.

```go
import "gno.land/p/moul/x/daily/fenwick/v0"

tr := fenwick.FromSlice([]int64{3, 1, 4, 1, 5})
tr.Prefix(3)          // 8    sum of [0, 3)
tr.Range(1, 4)        // 6    sum of [1, 4)
tr.Add(2, 10)         //      point update, O(log n)
tr.SearchPrefix(7)    // 2    the slot owning target 7
```

A realm that keeps a running tally is choosing between two bad options without
noticing. A plain slice updates in `O(1)` and sums in `O(n)`. A slice of running
totals sums in `O(1)` and updates in `O(n)`. A scoreboard is written by every
player *and* read by every page view, so it pays both costs. A Fenwick tree does
both in `O(log n)`, in exactly `n` values of storage, rearranged.

**The operation worth importing a package for is `SearchPrefix`**, not the prefix
sums. Given a target below `Total` it names the slot that owns it, in `O(log n)`,
by descending the tree rather than scanning it. That is the primitive behind a
stake-weighted draw (pick a number, ask who holds it) and behind a leaderboard's
rank lookup. Prefix sums alone would not justify a data structure.

Three behaviours worth knowing before you use it:

- **Reads are total, writes panic**, and the asymmetry is deliberate. `Prefix`,
  `Range`, `At`, `Covers` and `SearchPrefix` clamp whatever index they are
  handed; `Add`, `Set` and `New` panic. A read is what `Render` calls, and a
  realm cannot be redeployed on the same path, so a `Render` that panics on an
  out-of-range index is a page that is broken permanently. A write is a
  transaction, where aborting is the useful answer and the caller can still
  recover.
- **A zero-weight slot is never selected by `SearchPrefix`.** It falls out of the
  descent rather than being checked for: a zero does not advance the prefix, so
  no target can land on it. That is the property a weighted draw depends on, and
  the one a naive "first running total `>=` target" scan gets wrong.
- **`SearchPrefix` is only meaningful when every value is non-negative.** With a
  negative in the tree the prefix sums stop increasing and "the smallest index
  whose prefix exceeds the target" stops being well defined. Negative values are
  not forbidden, because `Add` with a negative delta is the ordinary way to
  decrement a counter; it is this one method that needs them absent.

`MaxSize` caps construction at 65,536 slots. Queries are `O(log n)` whatever the
size; the cap is there so the single `O(n)` operation, building the tree, cannot
be sized from unbounded user input. Sums must fit in `int64`, which gno does not
check and neither does this package.

`Covers(i)` reports which slots an internal node summarizes. It is not needed to
use the tree; it exists so the structure can be shown rather than asserted, and
the demo realm renders it.

Live demo: [`r/moul/x/daily/fenwickdemo`](/r/moul/x/daily/fenwickdemo/v0).
