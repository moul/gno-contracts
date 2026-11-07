# `gno.land/p/moul/x/daily/intervalset/v0`

**A set of half-open integer ranges, kept sorted, disjoint and coalesced**:
`New`, `Add`, `Remove`, `Contains`, `Covers`, `Overlaps`, `Spans`, `Measure`,
`Len`, `Clone`, `Clear`, `String`, `MaxSpans`.

```go
import "gno.land/p/moul/x/daily/intervalset/v0"

s := intervalset.New()
s.Add(100, 150)
s.Add(140, 210)   // overlaps: merged
s.Add(210, 260)   // only TOUCHES: merged anyway
s.String()        // "[100,260)" - one span, three writes
s.Contains(260)   // false: ranges are half-open
s.Measure()       // 160, counting the overlap once
```

**Realms keep ranges constantly**: vesting windows, sale periods, booking slots,
block-height gates, allowlisted id ranges. The obvious implementation is a slice
of pairs appended to on every write, and it is wrong in three ways that only
show up later:

- **It grows with the number of writes**, not with the shape of the data. On
  chain, storage is paid for once and kept forever, so a realm that accepts a
  thousand overlapping windows stores a thousand of them for good.
- **"Is this covered" becomes a linear scan** that gets slower with every write.
  Here it is `O(log n)` over spans whose count can only shrink as ranges are
  added.
- **Adding up the covered length double-counts every overlap.** That is the bug
  that makes such a list wrong for billing, and nothing about the list looks
  wrong.

Semantics worth knowing, each with a test:

- **Ranges are half-open**: `[Lo, Hi)` covers `Lo` and excludes `Hi`. That is
  what lets two touching ranges merge without overlapping, and it is the detail
  callers get wrong.
- **Touching merges, not just overlapping.** `[0,5)` and `[5,10)` are stored as
  `[0,10)`.
- **An empty or inverted range is a no-op**, on `Add` and `Remove` both, rather
  than a panic: a realm usually computes both ends from data and should not have
  to pre-check.
- **`Remove` from the middle of a span splits it**, and is the only operation
  that can raise the span count.
- **`Covers` and `Overlaps` are different questions**: may this range go ahead,
  versus does it clash with anything. `Covers` is answered by a single span,
  because the invariant guarantees a real gap between spans.
- **`Add` returns false only when the set is at `MaxSpans`** (1024) *and* the
  range would add a span. One that merges is always allowed: it cannot grow the
  count.

`Add`, `Remove` and `Measure` are `O(n)` in the number of spans; `Contains`,
`Covers` and `Overlaps` are `O(log n)`, and those are the ones a `Render` calls.

**Live demo:** [`r/moul/x/daily/intervalsetdemo`](https://github.com/moul/gno-contracts/tree/main/r/moul/x/daily/intervalsetdemo)
· render it at [`/r/moul/x/daily/intervalsetdemo/v0`](https://gno.land/r/moul/x/daily/intervalsetdemo/v0).
