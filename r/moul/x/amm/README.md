# amm: a constant-product AMM whose LP positions are real GRC20 tokens

A constant-product market maker for GRC20 pairs, many pools in one realm,
`x*y=k` with a 30 bps fee that stays with the liquidity providers. A liquidity
position is a **GRC20 token**, minted per pool and registered with
[`r/nt/grc20reg`](https://gno.land/r/nt/grc20reg/v0), so a position can be
transferred, approved, and priced by anything else on the chain.

Design study: [moul/gno-contracts#135](https://github.com/moul/gno-contracts/issues/135).

## The ledger-row design this replaced, and what it cost to leave it

The first cut of this realm kept a position as a row in a private `avl.Tree`.
That is the smaller thing, and it is what the realm shipped with until the
measurements below said the trade was worth taking. Both were built and run, so
the comparison is measured rather than argued, and the earlier shape is
recoverable from [#137](https://github.com/moul/gno-contracts/pull/137).

| | a private ledger row | a registered GRC20 |
|---|---|---|
| transferable | no | yes |
| approvable / usable as collateral | no | yes |
| readable by another realm | no | yes, via `grc20reg.Get(key)` |
| the realm must expose | nothing extra | 4 wrappers + `LPToken` |
| pool creation also does | nothing | mint a token, write a registry entry |
| allowance race surface | none | the standard GRC20 one |

Nothing about pricing, reserves, rounding or the guards moved: the ledger-row
version's `amm_test.gno` runs unmodified against this one, only the pkgpath
string differs. What moved is where a share lives.

Four identical operations, one `--- GAS:` figure each, from the same
`gas_test.gno` run against both. Fixture funding is measured separately so it
does not pollute the comparison:

| operation | ledger row | GRC20 | delta |
|---|---|---|---|
| seed (create pool + first deposit) | 1 716 207 | 2 213 407 | **+497 200 (+29.0%)** |
| swap | 1 459 531 | 1 459 531 | **0 (+0.0%)** |
| join (second provider) | 1 731 048 | 1 789 306 | +58 258 (+3.4%) |
| exit (full burn) | 1 433 236 | 1 518 298 | +85 062 (+5.9%) |

| | ledger row | GRC20 |
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
pool and ~5% on liquidity operations, and nothing at all on trading.** That is
why they are the default here, and why Uniswap V2 pairs are ERC20s.

## The LP API

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

`SharesOf` and `TotalShares` are `lp.BalanceOf` and `lp.TotalSupply`;
`AddLiquidity`, `RemoveLiquidity`, `Swap`, `AmountOut`, `Quote`, `Reserves`,
`PoolCount` and `Render` are unchanged by the LP decision.

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

## Warnings

- **Not an oracle.** The reserve ratio is a spot price any trader can move
  inside one transaction. Nothing should price off this realm.
- **`minOut` is your only slippage protection**, **a pool is only as honest as
  its two tokens**, and **none of this is audited**.
- **The LP `PrivateLedger` never leaves this realm.** It is the minting
  authority; exporting it, even indirectly, would let anyone mint positions
  against real reserves.

<!-- BEGIN GNOCONTRACTS FOOTER (generated by `make readmes`; do not edit below) -->

---

Part of **[moul/gno-contracts](https://github.com/moul/gno-contracts)** — moul's versioned gno.land contracts. See the repository for the full catalog, build/test tooling, and usage.

**Dependency graph:**

![gno.land/r/moul/x/amm/v0 dependency graph](https://raw.githubusercontent.com/moul/gno-contracts/main/_assets/gno.land/r/moul/x/amm/v0/deps.png)

> 🧪 **Highly experimental — potentially vibe-coded.** Not audited; may break, change, or be removed at any time. Do not use with anything of value. Full disclaimer: [DISCLAIMER](https://github.com/moul/gno-contracts/blob/main/DISCLAIMER.md).

<!-- END GNOCONTRACTS FOOTER -->
