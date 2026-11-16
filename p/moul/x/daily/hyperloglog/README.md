# `gno.land/p/moul/x/daily/hyperloglog/v0`

**How many DISTINCT elements a stream contained, in a fixed kilobyte**: `Add`, `Count`, `Merge`, `Snapshot`.

```go
import "gno.land/p/moul/x/daily/hyperloglog/v0"

s := hyperloglog.NewDefault()   // 1,024 registers, 1 KiB, ~3.25% standard error
s.Add("g1caller...")
s.Add("g1caller...")            // the same element moves nothing the second time
s.Add("g1other...")

s.Count()                       // → 2
s.Adds()                        // → 3, what arrived rather than what was different
s.Bytes()                       // → 1024, before and after a million elements

weekly.Merge(daily)             // the union, with the overlap counted once
store(s.Snapshot())             // the whole state is a []uint8
```

Counting unique anything on chain is normally a storage question rather than an arithmetic one. A set of addresses costs one stored object per address and grows with whatever users feed it, which is an unbounded bill driven by somebody else's behaviour. This costs 1,024 bytes at ten elements and 1,024 bytes at ten million, because it stores no elements at all: only the longest run of leading zeros each register was ever shown.

It is the third member of a family already in this catalog, and none of the three can answer another's question:

| question | structure |
|---|---|
| have I seen this one? | [`bloomfilter`](/r/moul/x/daily/bloomfilter) |
| how often did this one arrive? | [`countminsketch`](/p/moul/x/daily/countminsketch/v0) |
| how many different ones were there? | this one |

Four behaviours worth knowing before you use it:

- **It cannot tell you whether it has seen you.** Membership is not a weaker version of cardinality, it is a different question, and a sketch that has counted a million elements holds none of them. Nothing can be removed either: a register is a maximum, and a maximum cannot be undone.
- **There are two estimators and the switch between them is where naive implementations go wrong.** While most registers are still empty the answer comes from counting the empty ones (linear counting), which is exact until two elements collide. Once they are mostly full the harmonic mean takes over and the answer becomes an estimate with an error bar. The small-range branch is what makes `Count` return exactly 3 for three elements rather than 7.
- **The error does not depend on the cardinality.** `RelativeError` is `1.04/sqrt(m)` and nothing else, so the same kilobyte is about as wrong at a thousand elements as at a billion. It is one standard deviation, not a bound: about a third of sketches land outside it, so render it as "about 1,500 unique callers", never as 1,512.
- **`Merge` is why it beats a counter, not just a set.** It is a register-wise maximum, so shards counted separately combine into the union with the overlap counted once and without either side shipping its elements. It is idempotent for the same reason, which matters when the shards are days of history and a job gets re-run.

The large-range correction from the original paper is deliberately absent: it repairs 32-bit hash exhaustion and the hash here is 64 bits, so collisions start to matter past 10^18 elements. Hashing is FNV-1a followed by a splitmix64 finalizer, computed in pure gno. The finalizer is not decoration: the top `p` bits choose the register, FNV-1a leaves short inputs clustered exactly there, and clustering in the index means a handful of registers absorbing everything and a count that reads far too low.

`Snapshot` and `FromSnapshot` make the state a plain `[]uint8` a realm can store and restore, one slice rather than one object per element. A restored sketch reports `Adds() == 0`: it has observed nothing itself, and reporting somebody else's call count as its own is the kind of figure a `Render` would then repeat.

Precision runs from 4 to 16. Below that the bias constants are not defined; above it, 64 KiB buys a fraction of a percent.

Live demo: [`r/moul/x/daily/hyperloglogdemo`](/r/moul/x/daily/hyperloglogdemo/v0).
