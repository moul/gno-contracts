# Segment tree

> ⚠️ **Experimental.** Not audited. See [r/moul/x/daily](https://github.com/moul/gno-contracts/blob/main/r/moul/x/daily/README.md).

---

Eight readings, asked three different questions over the same windows, then one
slot rewritten to show what a write actually repairs.

Demo of the [`p/moul/x/daily/segmenttree`](https://github.com/moul/gno-contracts/tree/main/p/moul/x/daily/segmenttree)
library: the tree, the queries and the point update all come from the package;
this realm holds no logic of its own. Stateless and read-only, so `Render` is
fully deterministic and every figure on the page is computed from one fixed
slice rather than from chain state.

```
/r/moul/x/daily/segmenttreedemo/v0         → the slots, sum/min/max per window, the tree
/r/moul/x/daily/segmenttreedemo/v0:update  → one write, before and after, and what it cost
```

Two things the page is built to show. The empty window renders as `_empty_`
rather than as a number, because the library reports it with a `false` instead
of dressing the fold's identity up as an answer. And the tree is printed level
by level, so the claim that a window costs at most two nodes per level is
visible rather than asserted.

Built for gno 0.9.
