# Rock-Paper-Scissors Arena

> ⚠️ **Experimental — generated with no human supervision.** This realm was
> produced automatically by an MCP-driven agent to exercise the gno MCP server
> and tooling, and to generate test content for gno compilers, linters and
> formatters. **Not audited. Not for production.** Full context & folder README:
> [r/moul/daily/x](https://github.com/moul/gno-contracts/blob/main/r/moul/daily/x/README.md)

---


Best-of-three rock-paper-scissors against the house, played across multiple
calls instead of a single stateless throw. Each `Throw` plays one round of
your current match (starting a new one if you don't have one in progress);
the house's move is derived deterministically from the current block height,
a per-realm nonce, and your address. First to two round wins takes the
match, and every player's match record (wins, losses, rounds played) is
kept on-chain and viewable per-address.

**Realm path:** `gno.land/r/g12cs4cehujpffpjpywmkqj43m6u5ya53nj69sjz/rpsmatch`

## Example calls

```sh
# Play one round of your current (or a new) match
gnokey maketx call \
  -pkgpath "gno.land/r/g12cs4cehujpffpjpywmkqj43m6u5ya53nj69sjz/rpsmatch" \
  -func Throw -args "rock" \
  -gas-fee 1000000ugnot -gas-wanted 2000000 -broadcast -chainid test13 <key>

# View the arena dashboard
gnokey query vm/qrender \
  --data "gno.land/r/g12cs4cehujpffpjpywmkqj43m6u5ya53nj69sjz/rpsmatch:"

# View one player's record
gnokey query vm/qrender \
  --data "gno.land/r/g12cs4cehujpffpjpywmkqj43m6u5ya53nj69sjz/rpsmatch:g1youraddress..."
```

## Toolchain

Written against the test13 (gno 0.9) stdlib split (`chain`, `chain/runtime`,
`gno.land/p/nt/avl/v0`). The `gno` binary on `PATH` here is a newer/older
mismatch of its own `GNOROOT` (native-function drift), so tests were run
against a `gno` built from the exact pseudo-version pinned in that binary's
own module info (`github.com/gnolang/gno@v0.0.0-20260605043206-bf5b31eda8b9`).
All 5 tests pass (`gno test -v .`) and `gno lint .` is clean.
