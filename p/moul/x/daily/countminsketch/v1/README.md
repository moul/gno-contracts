# `gno.land/p/moul/x/daily/countminsketch/v1`

**Count–Min Sketch: frequency estimates in fixed space** — `New`, `NewDefault`,
`Add`, `AddN`, `Estimate`, `MightHave`, `Merge`, `Reset`, `Clone`, `Row`,
`Index`, `Total`, `Counters`.

```go
import "gno.land/p/moul/x/daily/countminsketch/v1"

s := countminsketch.NewDefault()   // 256 x 4 = 1024 counters, forever
for _, e := range stream { s.Add(e) }
s.Estimate("alice")   // an UPPER BOUND on how often "alice" appeared
s.MightHave("bob")    // false is definitive: never added
```

An exact frequency map costs one entry per distinct element — unbounded storage
driven by whatever users feed it, which on chain is a liability. A sketch is
sized **once** and never grows.

**The error is one-sided, and that is the whole contract: `Estimate` never
undercounts.** Collisions can only add other elements' counts to a row, so the
true frequency is always ≤ the estimate. Taking the minimum across `depth`
independently-seeded rows makes an overestimate require a collision in every row
at once. Treat the result as *"at most this often"*, never *"exactly this
often"*. The guarantee is tested against a deliberately tiny sketch where
collisions are certain.

Sizing: **width** controls the error, **depth** controls the odds of hitting it —
roughly, the overestimate stays within `total/width` with probability
`1 - (1/2)^depth`.

Hashing is FNV-1a with a per-row seed, computed in pure gno, so the counters are
identical on every node. `Distinct()` is deliberately absent — a Count–Min Sketch
cannot answer cardinality; use a HyperLogLog.

**Live demo:** [`r/moul/x/daily/countminsketchdemo`](https://github.com/moul/gno-contracts/tree/main/r/moul/x/daily/countminsketchdemo/v1)
· render it at [`/r/moul/x/daily/countminsketchdemo/v1`](https://gno.land/r/moul/x/daily/countminsketchdemo/v1).
