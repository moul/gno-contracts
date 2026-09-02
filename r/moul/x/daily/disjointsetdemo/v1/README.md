# Union-Find

> ⚠️ **Experimental — generated with no human supervision** by the daily MCP pipeline to exercise gno tooling. Not audited. See [r/moul/x/daily](https://github.com/moul/gno-contracts/blob/main/r/moul/x/daily/README.md).

---

Applies a fixed list of merges to `[0, 10)` and renders the resulting partition.

Demo of the [`p/moul/x/daily/disjointset`](https://github.com/moul/gno-contracts/tree/main/p/moul/x/daily/disjointset/v1)
library — every `Union`/`Find` comes from the package; this realm holds no
union-find logic. Stateless, so `Render` is fully deterministic.

The library's `Partition` is order-independent (groups sorted, ordered by
smallest member), which is exactly why the output can be pinned in an example
test at all.

Built for gno 0.9.
