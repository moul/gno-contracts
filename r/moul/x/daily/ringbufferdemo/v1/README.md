# Ring Buffer

> ⚠️ **Experimental — generated with no human supervision** by the daily MCP pipeline to exercise gno tooling. Not audited. See [r/moul/x/daily](https://github.com/moul/gno-contracts/blob/main/r/moul/x/daily/README.md).

---

Pushes six entries into a buffer of capacity four and renders, step by step,
what survived and what each overflowing push evicted.

Demo of the [`p/moul/x/daily/ringbuffer`](https://github.com/moul/gno-contracts/tree/main/p/moul/x/daily/ringbuffer/v1)
library — this realm holds no buffer logic of its own. Stateless, so `Render`
is fully deterministic.

Showing the evicted value in its own column is deliberate: it is the part of the
API that keeps a rolling window from dropping data silently.

Built for gno 0.9.
