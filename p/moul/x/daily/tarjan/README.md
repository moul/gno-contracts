# `gno.land/p/moul/x/daily/tarjan/v0`

**Strongly connected components of a directed graph** — `New`, `FromPairs`,
`Add`, `Edge`, `Components`, `ComponentOf`, `Cyclic`, `Nodes`, `Successors`,
`String`.

Finds the maximal groups of nodes that can all reach each other: the tangles, not
just the fact that one exists.

```go
import "gno.land/p/moul/x/daily/tarjan/v0"

g := tarjan.FromPairs([][2]string{
    {"app", "auth"}, {"auth", "session"}, {"session", "auth"},
})
g.Components()  // [["auth" "session"] ["app"]]
g.Cyclic()      // true
```

**Why not just a cycle check.** A dependency checker that answers yes leaves the
caller to go and find the knot. `Components` hands back the knot itself, and
since collapsing each component to a point turns any graph into a DAG, the
components come out already ordered: reverse topological, so reading the list
top to bottom is a safe build order where each entry is either a single node or
a group that has to be handled as a unit. A node in no cycle is a component of
exactly one, so the ordinary acyclic case needs no special handling.

**`Cyclic` is not `len(component) > 1`.** A node pointing at itself is a cycle
and its component holds one node, the same size as every acyclic node's, so the
self edge has to be checked separately. That is the case this package is most
likely to be asked about and the one a size test silently gets wrong.

**No recursion.** Tarjan's algorithm is almost always written recursively, which
costs one call frame per node of depth; this keeps its own explicit stack
instead, so a 2,000-node chain is fine (pinned by a test) rather than a VM stack
limit.

**Deterministic by construction.** Nodes are kept in insertion order and the map
is a name lookup only: every traversal walks a name-sorted permutation, so no
map is ever *iterated*. Walk roots are taken smallest name first, successors in
name order, and each component is sorted before it is returned. The same edge
set declared in a different order produces byte-identical output, which a test
pins — a realm whose `Render` reshuffled between identical calls would be a
consensus bug.

Edge cases: duplicate edges collapse; empty names are rejected rather than
creating a `""` node; a self edge is kept and reported as a one-node cycle;
`Nodes` and `Successors` return copies, so a caller cannot mutate the graph
through them; `ComponentOf` on an unknown name returns nothing rather than an
empty component.

**Live demo:** [`r/moul/x/daily/tarjandemo`](https://github.com/moul/gno-contracts/tree/main/r/moul/x/daily/tarjandemo)
· render it at [`/r/moul/x/daily/tarjandemo/v0`](https://gno.land/r/moul/x/daily/tarjandemo/v0).
