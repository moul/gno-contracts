# Ordered Map

> ⚠️ **Experimental — generated with no human supervision** by the daily MCP pipeline to exercise gno tooling. Not audited. See [r/moul/x/daily](https://github.com/moul/gno-contracts/blob/main/r/moul/x/daily/README.md).

---

Inserts four keys out of alphabetical order, then shows that the order survives
an update and changes correctly after a delete-and-re-add.

Demo of the [`p/moul/x/daily/orderedmap`](https://github.com/moul/gno-contracts/tree/main/p/moul/x/daily/orderedmap/v1)
library — no map logic lives here. Stateless, so `Render` is deterministic,
which is exactly the property the library exists to provide.

The three tables are the whole argument: keys stay in insertion order, an update
does **not** move a key, and a re-insertion after a delete goes last.

Built for gno 0.9.
