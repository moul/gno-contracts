# `gno.land/p/moul/x/daily/toposort/v1`

**Topological sort of a dependency graph** — `New`, `FromPairs`, `Add`,
`DependOn`, `Sort`, `CycleNodes`, `Nodes`, `DependenciesOf`, `String`.

Orders a graph so every node comes after everything it depends on — the "install
these packages in a safe order" problem — using Kahn's algorithm.

```go
import "gno.land/p/moul/x/daily/toposort/v1"

g := toposort.FromPairs([][2]string{
    {"realm", "ui"}, {"ui", "markdown"}, {"markdown", "strings"},
})
order, err := g.Sort()   // ["strings" "markdown" "ui" "realm"], nil
```

**Deterministic by construction.** Among nodes that become ready at the same
time, the lexicographically smallest is always emitted first, so a given graph
has exactly one possible answer regardless of insertion order. Adjacency is kept
in sorted slices and no map is ever *iterated* — Go/gno map iteration order is
unspecified, and a realm whose `Render` reshuffled between identical calls would
be a bug.

A cycle is **reported, not hidden**: `Sort` returns `ErrCycle` along with the
partial order it managed, and `CycleNodes` names the nodes still stuck so a
caller can say exactly which dependencies are tangled.

Edge cases: a self-dependency is ignored as a trivial cycle but the node stays
in the graph; duplicate edges collapse; empty names are rejected; `Nodes` and
`DependenciesOf` return copies, so a caller cannot mutate the graph through them.

**Live demo:** [`r/moul/x/daily/toposortdemo`](https://github.com/moul/gno-contracts/tree/main/r/moul/x/daily/toposortdemo/v1)
· render it at [`/r/moul/x/daily/toposortdemo/v1`](https://gno.land/r/moul/x/daily/toposortdemo/v1).
