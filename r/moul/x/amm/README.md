# amm v1: the same AMM, with LP positions as real GRC20 tokens

Same constant-product market maker as [`v0`](../v0), same pricing, same
reserves, same guards. One thing changes: a liquidity position is a **GRC20
token**, minted per pool and registered with
[`r/nt/grc20reg`](https://gno.land/r/nt/grc20reg/v0), instead of a row in a
private avl ledger.

The two exist side by side on purpose. v0 is the smallest thing that works; v1
is what it costs to make positions first-class. The numbers are below, measured
rather than asserted.

Design study: [moul/gno-contracts#135](https://github.com/moul/gno-contracts/issues/135).

## What changes

`v0/amm_test.gno` runs unmodified against v1 (only the pkgpath string differs),
so nothing about pricing, reserves, rounding or the guards moved. What moved is
where a share lives:

| | v0 | v1 |
|---|---|---|
| a position is | a row in a private `avl.Tree` | a balance on a registered GRC20 |
| transferable | no | yes |
| approvable / usable as collateral | no | yes |
| readable by another realm | no | yes, via `grc20reg.Get(key)` |
| the realm must expose | nothing extra | 4 wrappers + `LPToken` |
| pool creation also does | nothing | mint a token, write a registry entry |
| allowance race surface | none | the standard GRC20 one |

## Cost, measured

Four identical operations, one `--- GAS:` figure each, from the same
`gas_test.gno` present verbatim in both versions. Fixture funding is measured
separately so it does not pollute the comparison:

| operation | v0 | v1 | delta |
|---|---|---|---|
| seed (create pool + first deposit) | 1 716 207 | 2 213 407 | **+497 200 (+29.0%)** |
| swap | 1 459 531 | 1 459 531 | **0 (+0.0%)** |
| join (second provider) | 1 731 048 | 1 789 306 | +58 258 (+3.4%) |
| exit (full burn) | 1 433 236 | 1 518 298 | +85 062 (+5.9%) |

| | v0 | v1 |
|---|---|---|
| `amm.gno`, total lines | 506 | 589 |
| `amm.gno`, code lines | 333 | 359 |
| exported functions | 10 | 15 |

The shape of that is the interesting part. **Swapping is unaffected to the
gas unit**, because the hot path never touches share accounting: it reads two
reserves, prices, moves two token balances, writes two reserves. The whole
premium is paid where positions are created and destroyed. Pool creation
carries it almost entirely, once, as a fixed setup cost: minting the LP token
and registering it. Per-provider operations pay 3 to 6 percent.

Read the other way: **transferable LP positions cost a one-off ~0.5M gas per
pool and ~5% on liquidity operations, and nothing at all on trading.**

## What v1 adds to the API

```go
LPToken(keyA, keyB string) string                 // the pool's LP token registry key
AllowanceLP(keyA, keyB string, owner, spender address) int64
TransferLP(cur realm, keyA, keyB string, to address, amount int64)
ApproveLP(cur realm, keyA, keyB string, spender address, amount int64)
TransferFromLP(cur realm, keyA, keyB string, from, to address, amount int64)
```

The four wrappers exist because the LP token lives *in this realm*: a signing
user has no token realm of its own to call, the way they would for any other
GRC20. A **realm** holding LP does not need them and can move its own balance
through the registry:

```go
grc20reg.Transfer(0, cur, amm.LPToken(keyA, keyB), to, n)
```

`ApproveLP` carries the usual GRC20 approve race: an allowance lowered from a
non-zero value can be spent at both the old and the new figure under unlucky
ordering. Set it to 0 first.

Everything else (`AddLiquidity`, `RemoveLiquidity`, `Swap`, `AmountOut`,
`Quote`, `Reserves`, `SharesOf`, `TotalShares`, `PoolCount`, `Render`) keeps
the v0 signature and the v0 behaviour. `SharesOf` and `TotalShares` are now
just `lp.BalanceOf` and `lp.TotalSupply`.

## LP token naming

One token per pool, symbol `LP<n>` from a never-reset counter, name
`AMM LP <symA>/<symB>`, decimals mirroring token A (the LP unit is token A at
seed time). The symbol is a counter and not the pair because `grc20` caps a
symbol at 11 characters, which `LP-` plus two 11-character symbols would blow
straight past; the readable pair goes in the name, which allows 64.

Never resetting the counter is what keeps `grc20reg`'s
one-token-per-realm-and-symbol rule satisfiable forever: a drained pool keeps
its LP token and identity, and reseeding reuses it rather than minting a
second token under a symbol already taken.

## Which one to use

**v0** if positions never need to leave the address that opened them: a
personal pool, a closed system, or anywhere the extra 5 exported functions and
the allowance surface are pure liability.

**v1** if anything else in the ecosystem should be able to see, hold, price or
lend against a position. That is the normal expectation for an AMM, and it is
why Uniswap V2 pairs are ERC20s.

Everything under [`v0`'s README](../v0/README.md) about reserves being stored
rather than read from balances, the missing `sqrt`, the `int64` ceiling and the
decimals table applies here unchanged.

## Warnings

- **Not an oracle**, **`minOut` is your only slippage protection**, **a pool is
  only as honest as its two tokens**, **not audited**. Same as v0, same
  reasons, see [`v0`'s README](../v0/README.md).
- **The LP `PrivateLedger` never leaves this realm.** It is the minting
  authority; exporting it, even indirectly, would let anyone mint positions
  against real reserves.
