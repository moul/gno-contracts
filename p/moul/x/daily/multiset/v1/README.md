# `gno.land/p/moul/x/daily/multiset/v1`

**Bag / frequency counter** — `New`, `FromSlice`, `Add`, `AddN`, `Remove`,
`RemoveN`, `RemoveAll`, `Count`, `MostCommon`, `Union`, `Intersect`, `Sum`,
`Elements`, `Expand`, `Clone`, `MaxDistinct`.

```go
import "gno.land/p/moul/x/daily/multiset/v1"

m := multiset.FromSlice([]string{"a", "a", "a", "b", "b", "c"})
m.Count("a")        // 3
m.MostCommon(2)     // [{a 3} {b 2}]
m.Total()           // 6 occurrences
m.Distinct()        // 3 elements
```

The STL `multiset` and Python's `collections.Counter` in one type.

**`MostCommon` has a total order:** count descending, then element ascending.
Sorting by count alone would leave ties in whatever order the backing map
yielded — unspecified in gno, and enough to make two nodes render different
tables from identical state. The tiebreak is not decoration.

Semantics worth knowing, each with a test:

- **A count reaching zero removes the element**, rather than leaving a
  zero-count ghost that `Distinct` would still count.
- **`RemoveN` clamps**: removing more than are present clears the element
  instead of going negative.
- `Union` takes the **max** of each count, `Intersect` the **min** (common
  elements only), `Sum` adds them.

`MaxDistinct` (4096) bounds the number of *distinct* elements; counts themselves
are unbounded, so a full set still accepts more occurrences of what it holds.

**Live demo:** [`r/moul/x/daily/multisetdemo`](https://github.com/moul/gno-contracts/tree/main/r/moul/x/daily/multisetdemo/v1)
· render it at [`/r/moul/x/daily/multisetdemo/v1`](https://gno.land/r/moul/x/daily/multisetdemo/v1).
