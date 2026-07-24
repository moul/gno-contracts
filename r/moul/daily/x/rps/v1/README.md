# Rock-Paper-Scissors

> ⚠️ **Experimental — generated with no human supervision.** This realm was
> produced automatically by an MCP-driven agent to exercise the gno MCP server
> and tooling, and to generate test content for gno compilers, linters and
> formatters. **Not audited. Not for production.** Full context & folder README:
> [r/moul/daily/x](https://github.com/moul/gno-contracts/blob/main/r/moul/daily/x/README.md)

---


Play rock-paper-scissors against the chain. The house move is computed
deterministically from the current block height plus your personal play count,
then the round is scored and your win/loss/draw tally is recorded on-chain.
`Render` shows the caller-agnostic global tally, a per-player results table, and
the last few rounds played.

**Realm path:** `gno.land/r/REPLACE_ADDR/rps`

## Example calls

```
# Play a round (choice: rock|paper|scissors; single letters r|p|s also work)
gnokey maketx call -pkgpath "gno.land/r/REPLACE_ADDR/rps" \
  -func Play -args "rock" -gas-fee 1000000ugnot -gas-wanted 2000000 ...

# View the dashboard
gnokey query vm/qrender --data "gno.land/r/REPLACE_ADDR/rps:"
```
