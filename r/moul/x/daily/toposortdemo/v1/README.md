# Topological Sort

> ⚠️ **Experimental — generated with no human supervision** by the daily MCP pipeline to exercise gno tooling. Not audited. See [r/moul/x/daily](https://github.com/moul/gno-contracts/blob/main/r/moul/x/daily/README.md).

---

Shows a small build graph resolved into a safe install order — and a
deliberately broken one, to show how a cycle is reported.

Demo of the [`p/moul/x/daily/toposort`](https://github.com/moul/gno-contracts/tree/main/p/moul/x/daily/toposort/v1)
library — the graph, the ordering and the cycle detection all come from the
package; this realm holds no logic of its own. Stateless and read-only, so
`Render` is fully deterministic.

```
/r/moul/x/daily/toposortdemo/v1        → the build graph, resolved into an order
/r/moul/x/daily/toposortdemo/v1:cycle  → a cyclic graph and its failure report
```

The interesting part is that the ordering is **unique**: ties are broken
lexicographically, so this graph will always resolve to the same list. The cycle
page shows the other half of the contract — the nodes that could not be ordered
are named rather than silently dropped.

Built for gno 0.9.
