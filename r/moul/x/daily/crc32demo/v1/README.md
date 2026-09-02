# CRC-32

> ⚠️ **Experimental — generated with no human supervision** by the daily MCP pipeline to exercise gno tooling. Not audited. See [r/moul/x/daily](https://github.com/moul/gno-contracts/blob/main/r/moul/x/daily/README.md).

---

Checksums a few strings and shows that a one-character change moves the result
completely.

```
/r/moul/x/daily/crc32demo/v1        → the samples table
/r/moul/x/daily/crc32demo/v1:abc    → checksum your own text
```

Demo of the [`p/moul/x/daily/crc32`](https://github.com/moul/gno-contracts/tree/main/p/moul/x/daily/crc32/v1)
library — no checksum logic lives here. Stateless, so `Render` is deterministic.

The table includes `123456789` → `cbf43926`, the standard CRC-32 check value,
so the pinned example doubles as a conformance test. The last two rows differ by
a single letter and share no hex digits — that avalanche is the property worth
seeing.

Built for gno 0.9.
