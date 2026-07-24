# RingLog

> ⚠️ **Experimental — generated with no human supervision.** This realm was
> produced automatically by an MCP-driven agent to exercise the gno MCP server
> and tooling, and to generate test content for gno compilers, linters and
> formatters. **Not audited. Not for production.** Full context & folder README:
> [r/moul/daily/x](https://github.com/moul/gno-contracts/blob/main/r/moul/daily/x/README.md)

---


A port of Go's `container/ring` onto gno.land — a fixed-capacity circular message board where new posts automatically evict the oldest once the buffer fills up. Holds the last 16 messages on-chain; no pagination, no clutter.

**Realm:** `gno.land/r/g12cs4cehujpffpjpywmkqj43m6u5ya53nj69sjz/ringlog`

## How it works

The realm maintains a 16-slot ring buffer backed by a fixed-size array. `head` tracks the next write position; when it wraps past the end it overwrites the oldest slot. Classic O(1) insert, O(n) read — no allocations after init.

## Transactions

```bash
# Post a message (up to 280 chars)
gnokey maketx call -pkgpath "gno.land/r/g12cs4cehujpffpjpywmkqj43m6u5ya53nj69sjz/ringlog" \
  -func Post -args "hello gno.land" \
  -gas-fee 1000000ugnot -gas-wanted 2000000 \
  -broadcast -chainid test13 \
  -remote https://rpc.test13.gnoteam.com:443 \
  <keyname>
```

## Queries

```bash
# View via gnoweb
open "https://test13.gno.land/r/g12cs4cehujpffpjpywmkqj43m6u5ya53nj69sjz/ringlog"

# Get entries programmatically
gnokey query vm/qeval \
  -remote https://rpc.test13.gnoteam.com:443 \
  -data 'gno.land/r/g12cs4cehujpffpjpywmkqj43m6u5ya53nj69sjz/ringlog.Len()'
```

## Capacity

The buffer holds exactly **16** messages (`Cap = 16`). Once full, the next `Post` silently drops the oldest. This mirrors `container/ring.Ring.Move` with overwrite semantics.
