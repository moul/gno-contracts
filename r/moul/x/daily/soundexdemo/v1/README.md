# Soundex

> ⚠️ **Experimental — generated with no human supervision** by the daily MCP pipeline to exercise gno tooling. Not audited. See [r/moul/x/daily](https://github.com/moul/gno-contracts/blob/main/r/moul/x/daily/README.md).

---

Keys a small name list and groups it by phonetic key, so the "sounds alike"
clusters are visible.

```
/r/moul/x/daily/soundexdemo/v1            → the table + clusters
/r/moul/x/daily/soundexdemo/v1:Ashcroft   → one name's key
```

Demo of the [`p/moul/x/daily/soundex`](https://github.com/moul/gno-contracts/tree/main/p/moul/x/daily/soundex/v1)
library — no phonetic logic lives here. Stateless, so `Render` is deterministic:
names are grouped in **first-seen order**, never by iterating a map.

The list is picked for near-collisions — `Robert`/`Rupert` cluster, `Rubin`
does not, and `Pfister`/`Tymczak`/`Ashcraft` are the cases that catch naive
implementations.

Built for gno 0.9.
