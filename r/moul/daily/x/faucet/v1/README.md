# Token Faucet

> ⚠️ **Experimental — generated with no human supervision.** This realm was
> produced automatically by an MCP-driven agent to exercise the gno MCP server
> and tooling, and to generate test content for gno compilers, linters and
> formatters. **Not audited. Not for production.** Full context & folder README:
> [r/moul/daily/x](https://github.com/moul/gno-contracts/blob/main/r/moul/daily/x/README.md)

---


A toy points faucet realm for the gno.land test13 testnet. Any caller can
`Claim` 100 points, but only once every 100 blocks per address — the cooldown is
enforced deterministically via `runtime.ChainHeight()`. Per-caller balances and
last-claim heights are stored in an `avl.Tree`, and `Render` shows the total
distributed, total claim count, and a table of all claimers with their balances.

## Realm path

```
gno.land/r/REPLACE_ADDR/faucet
```

(`REPLACE_ADDR` is replaced with the deploy address at deploy time.)

## Example calls

```sh
# Claim 100 points (subject to the 100-block cooldown).
gnokey maketx call -pkgpath "gno.land/r/REPLACE_ADDR/faucet" \
  -func Claim -gas-fee 1000000ugnot -gas-wanted 2000000 -broadcast \
  -chainid test13 mykey

# Query a balance (read-only).
gnokey query "vm/qeval" -data \
  'gno.land/r/REPLACE_ADDR/faucet.BalanceOf("g1...youraddr")'

# View the dashboard.
gnokey query "vm/qrender" -data 'gno.land/r/REPLACE_ADDR/faucet:'
```

## Behavior

- `Claim(cur realm)` — grants `ClaimAmount` (100) points to the caller; aborts if
  the caller's previous claim was less than `CooldownBlocks` (100) blocks ago.
- `BalanceOf(addr string) int64` — current balance for an address (0 if unknown).
- `Render(path string) string` — Markdown dashboard: stats + claimer table.
