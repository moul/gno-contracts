# LRU Cache

> ⚠️ **Experimental — generated with no human supervision.** This realm was
> produced automatically by an MCP-driven agent to exercise the gno MCP server
> and tooling, and to generate test content for gno compilers, linters and
> formatters. **Not audited. Not for production.** Full context & folder README:
> [r/moul/daily/x](https://github.com/moul/gno-contracts/blob/main/r/moul/daily/x/README.md)

---


A fixed-capacity (8) least-recently-used cache realm — a port of the classic
LRU. `Put` inserts or updates an entry and marks it most-recently-used, evicting
the least-recently-used entry when capacity is exceeded. `Get` returns a value,
bumps its recency, and records a hit or a miss. `Render` shows the entries in
MRU→LRU order alongside the capacity and hit/miss stats.

Realm path: `gno.land/r/REPLACE_ADDR/lru`

## Example calls

```
# insert / update entries (marks them most-recently-used)
Put("a", "1")
Put("b", "2")

# read a value (counts a hit, bumps recency)
Get("a")   # -> "1", true

# read a missing key (counts a miss)
Get("zzz") # -> "", false

# clear everything
Reset()

# view state (MRU→LRU order + stats)
Render("")
```
