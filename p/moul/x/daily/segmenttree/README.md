# `gno.land/p/moul/x/daily/segmenttree/v0`

**Range sum, minimum and maximum over the same slots, each in `O(log n)`, with
any single slot rewritable in `O(log n)` too**: `New`, `NewSum`, `NewMin`,
`NewMax`, `Query`, `Total`, `At`, `Set`, `Add`, `Values`, `Nodes`, `Depth`.

```go
import "gno.land/p/moul/x/daily/segmenttree/v0"

t := segmenttree.NewMin([]int64{3, 1, 4, 1, 5, 9, 2, 6})
v, ok := t.Query(4, 8)   // 2, true   (half-open, like a slice)
t.Set(5, 0)              // one write, O(log n), no rebuild
v, ok = t.Query(4, 8)    // 0, true
```

A realm that keeps a window of readings (scores, stakes, prices, votes per
block) gets asked two kinds of question about them, and the obvious structures
answer only one each. A plain slice answers any window in `O(n)`. A running
prefix-sum array answers it in `O(1)` and then costs `O(n)` to repair after a
single write. [`fenwick`](https://github.com/moul/gno-contracts/tree/main/p/moul/x/daily/fenwick) fixes the write but is built on
subtraction, so it does sums and cannot do minimum or maximum at all. This
structure keeps the combined value of every subrange, which makes the three
questions one walk with a different fold.

**The fold is an enum, not a function value, deliberately.** `Op` is `Sum`,
`Min` or `Max`. A realm persists its tree, and a persisted object may not hold
a closure, so a `combine func(a, b int64) int64` field would make the whole
structure unstorable on chain for the sake of a generality nobody asked for.
An unrecognised `Op` is read as `Sum` rather than panicking: a constructor that
panics takes down the realm's `init`.

Three behaviours worth knowing before you use it:

- **Nothing panics, and every accessor has a second return value.** `Query` on
  a reversed, empty or out-of-bounds window reports `false`. The value handed
  back with it is the fold's identity, which for `Min` is
  `9223372036854775807`: a number that must never reach a page, and the reason
  the `false` is not optional. A `Render` that panics is a page nobody can read
  again, and a public realm path cannot be redeployed.
- **The slots are copied, in and out.** `New` copies the caller's slice and
  `Values` returns a copy. A caller holding the same backing array could
  otherwise edit a leaf and leave every parent above it stale, which is the one
  failure mode of this structure that is invisible until a query returns a
  plausible wrong number.
- **`Nodes` reports the tree, not the padding.** The slots are padded up to a
  power of two so every node covers an aligned range; the padding holds the
  fold's identity and `Nodes` drops any node that covers nothing real, clamping
  the rest to `Len`. That is what lets a demo draw the structure instead of
  describing it.

Cost: `2 * next_power_of_two(n)` int64 slots, so up to twice the data in the
worst case, which is the price of the aligned ranges. `Sum` wraps on int64
overflow, exactly as `+` does; a realm summing balances should cap what it
stores rather than hoping. Construction is `O(n)`, every other operation is
`O(log n)`.

**Live demo:** [`r/moul/x/daily/segmenttreedemo`](https://github.com/moul/gno-contracts/tree/main/r/moul/x/daily/segmenttreedemo)
· render it at [`/r/moul/x/daily/segmenttreedemo/v0`](https://gno.land/r/moul/x/daily/segmenttreedemo/v0).
