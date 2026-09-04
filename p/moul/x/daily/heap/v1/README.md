# `gno.land/p/moul/x/daily/heap/v1`

**Binary heap / priority queue** — `New`, `NewMax`, `Push`, `Pop`, `Peek`,
`Drain`, `Clone`, `Len`, `IsEmpty`, `IsMax`, `MaxItems`.

```go
import "gno.land/p/moul/x/daily/heap/v1"

h := heap.New()          // min-heap; NewMax() for max
h.Push("pay invoice", 1)
h.Push("clear cache", 9)
h.Peek()                 // "pay invoice", 1, true — does not remove
h.Drain()                // ["pay invoice" "clear cache"]
```

Go's `container/heap` makes you implement five methods and hands back an
interface. This is the concrete structure instead: an implicit binary heap in a
slice, `Push`/`Pop` in O(log n), `Peek` in O(1).

**The ordering is total.** Equal priorities pop **oldest-first**, and that
tiebreak does *not* invert in a max-heap — only the priority comparison does.
Without it, ties would fall back on whatever order the backing slice happened to
hold, and two nodes could pop the same queue differently: a consensus bug, not a
cosmetic one.

`MaxItems` (4096) bounds growth; a full heap refuses new items rather than
growing without limit.

**Live demo:** [`r/moul/x/daily/heapdemo`](https://github.com/moul/gno-contracts/tree/main/r/moul/x/daily/heapdemo/v1)
· render it at [`/r/moul/x/daily/heapdemo/v1`](https://gno.land/r/moul/x/daily/heapdemo/v1).
