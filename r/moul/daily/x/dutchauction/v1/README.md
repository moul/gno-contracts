# dutchauction

> ⚠️ **Experimental — generated with no human supervision.** This realm was
> produced automatically by an MCP-driven agent to exercise the gno MCP server
> and tooling, and to generate test content for gno compilers, linters and
> formatters. **Not audited. Not for production.** Full context & folder README:
> [r/moul/daily/x](https://github.com/moul/gno-contracts/blob/main/r/moul/daily/x/README.md)

---


A Gno port of the classic Solidity Dutch-auction pattern: list an item at a
high starting price that decays linearly, block by block, down to a floor.
The first buyer to call `Buy` gets it at whatever the price is at that exact
block — no bidding war, just a clock ticking against the seller. Payment is
real `ugnot`, escrowed by the chain with the transaction; overpayment is
refunded automatically and the settled price is forwarded straight to the
seller.

Realm path: `gno.land/r/g12cs4cehujpffpjpywmkqj43m6u5ya53nj69sjz/dutchauction`

## Example calls

```
# list an item: 1000 ugnot down to a 100 ugnot floor over 100 blocks
List(cur, "vintage synth", 1000, 100, 100) -> "1"

# anyone can check the live price without paying anything
CurrentPrice("1") -> 1000, decaying toward 100 as blocks pass

# buy at the current price, sending >= CurrentPrice("1") ugnot with the tx;
# any excess is refunded in the same call
Buy(cur, "1") -> price actually paid

# the seller can pull a listing before anyone buys it
Cancel(cur, "1")
```

`Render("")` lists every auction with its live price, floor, start price,
and status.

## Toolchain status

`gno test .` passes (7/7) against `gnolang/gno` master (`master.3130+bf5b31eda`)
with `GNOROOT` pointed at a full checkout — the local `gno` on `PATH` ships
without a bundled stdlib tree, so `GNOROOT` had to be set explicitly to
resolve `chain`, `chain/banker`, `chain/runtime`, and
`gno.land/p/nt/avl/v0`/`testutils/v0`. `gno lint .` is clean. Target chain is
test13 (gno 0.9); code sticks to the documented `chain/*` stdlib family and
crossing-function (`cur realm`) convention used by the other realms in this
batch.
