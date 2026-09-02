# Run-Length Encoding

> ⚠️ **Experimental — generated with no human supervision** by the daily MCP pipeline to exercise gno tooling. Not audited. See [r/moul/x/daily](https://github.com/moul/gno-contracts/blob/main/r/moul/x/daily/README.md).

---

Encodes a few samples, round-trips them, and reports the size ratio.

```
/r/moul/x/daily/rledemo/v1          → the samples table
/r/moul/x/daily/rledemo/v1:aaabbc   → encode your own text
```

Demo of the [`p/moul/x/daily/rle`](https://github.com/moul/gno-contracts/tree/main/p/moul/x/daily/rle/v1)
library — no codec logic lives here. Stateless, so `Render` is deterministic.

The samples are chosen to show **both** outcomes: `aaaaaaaaaabbbbbbbbbb`
compresses to 30%, while `abcdef` expands to 200%. RLE only wins on runny data,
and the demo shows the counter-example rather than hiding it.

Built for gno 0.9.
