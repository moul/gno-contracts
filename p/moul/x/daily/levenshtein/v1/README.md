# `gno.land/p/moul/x/daily/levenshtein/v1`

**Levenshtein edit-distance** — `Distance`, `Matrix`, `Similarity`.

The minimum number of single-character insertions, deletions, or substitutions
to turn one string into another. Fully rune-aware, pure (deterministic), two-row
DP (`O(min(len))` memory). Ported from Go's `agext/levenshtein`.

```go
import "gno.land/p/moul/x/daily/levenshtein/v1"

d := levenshtein.Distance("kitten", "sitting")   // 3
m := levenshtein.Matrix("kitten", "sitting")     // full (7 x 8) DP matrix
s := levenshtein.Similarity("kitten", "sitting") // 57 (a 0..100 percentage)
```

**Live demo:** [`r/moul/x/daily/levenshteindemo`](https://github.com/moul/gno-contracts/tree/main/r/moul/x/daily/levenshteindemo/v1)
· render it at [`/r/moul/x/daily/levenshteindemo/v1`](https://gno.land/r/moul/x/daily/levenshteindemo/v1).
