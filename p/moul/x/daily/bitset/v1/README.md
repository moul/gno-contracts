# `gno.land/p/moul/x/daily/bitset/v1`

**Dense fixed-capacity bit vector** — `New`, `FromSlice`, `Set`, `Clear`, `Flip`,
`Has`, `Count`, `Slice`, `Clone`, `Union`, `Intersect`, `Difference`,
`SymmetricDifference`, `Equal`, `MaxBits`.

A compact set of small non-negative integers. Storage is `[]uint64` of
`ceil(n/64)` words, so 1024 bits cost 16 words instead of 1024 booleans — the
reason to reach for this on chain, where every byte is paid for.

```go
import "gno.land/p/moul/x/daily/bitset/v1"

b := bitset.FromSlice(20, []int{1, 2, 3})
c := bitset.FromSlice(20, []int{3, 4})
bitset.Union(b, c).Slice()       // [1 2 3 4]
bitset.Intersect(b, c).Slice()   // [3]
b.Count()                        // 3
```

Capacity is **fixed** at construction: operations are bounds-checked and return
`false` out of range rather than growing, because silent growth would make gas
unpredictable. `Has` on an out-of-range index is simply `false` — something that
cannot be a member is not a member.

Combining two sets of **different** capacities returns `nil` rather than padding
one silently; a size mismatch is a caller error worth surfacing.

`MaxBits` (65536) caps allocation. Note `String()` prints bit 0 first, so it
reads in index order — the reverse of binary notation.

**Live demo:** [`r/moul/x/daily/bitsetdemo`](https://github.com/moul/gno-contracts/tree/main/r/moul/x/daily/bitsetdemo/v1)
· render it at [`/r/moul/x/daily/bitsetdemo/v1`](https://gno.land/r/moul/x/daily/bitsetdemo/v1).
