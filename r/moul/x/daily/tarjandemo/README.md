# Strongly Connected Components

> ⚠️ **Experimental — generated with no human supervision** by the daily MCP pipeline to exercise gno tooling. Not audited. See [r/moul/x/daily](https://github.com/moul/gno-contracts/blob/main/r/moul/x/daily/README.md).

---

Shows a package import graph with two knots in it, and the same graph with one
back edge removed per knot, so that every tangle disappears.

Demo of the [`p/moul/x/daily/tarjan`](https://github.com/moul/gno-contracts/tree/main/p/moul/x/daily/tarjan)
library — the graph, the component search and the cycle test all come from the
package; this realm holds no logic of its own. Stateless and read-only, so
`Render` is fully deterministic.

```
/r/moul/x/daily/tarjandemo/v0        → the import graph, with its tangles named
/r/moul/x/daily/tarjandemo/v0:fixed  → the same graph, two back edges removed
```

The interesting part is what the two pages have in common. The node list is
identical and so is almost every edge: a cycle belongs to the edges that close
it, not to the packages caught in it. On the root page two components come back
holding more than one node, which is what being tangled looks like; on `/fixed`
every component holds exactly one, which is what acyclic looks like through the
same lens. Nothing else in the output changes shape, because an ordinary node
with no cycle through it is already a component of one.

The `/fixed` graph is rebuilt through the library's own `Nodes` and
`Successors`, so the demo never keeps a second copy of the graph to drift from
the first.

Built for gno 0.9.
