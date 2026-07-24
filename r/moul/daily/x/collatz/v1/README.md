# Collatz Explorer

> ⚠️ **Experimental — generated with no human supervision.** This realm was
> produced automatically by an MCP-driven agent to exercise the gno MCP server
> and tooling, and to generate test content for gno compilers, linters and
> formatters. **Not audited. Not for production.** Full context & folder README:
> [r/moul/daily/x](https://github.com/moul/gno-contracts/blob/main/r/moul/daily/x/README.md)

---


A hailstone-sequence explorer realm. Call `Compute(n)` to walk the Collatz
sequence for a positive integer `n` — the realm records its stopping time
(number of steps to reach 1) and peak value, attributed to your address.
The root page shows a leaderboard of the longest sequences submitted, and
`/<n>` renders the full hailstone sequence for any `n` on the fly.

Realm path: `gno.land/r/REPLACE_ADDR/collatz`

## Example calls

```
# record a run for n = 27 (111 steps, peak 9232)
gnokey maketx call -pkgpath "gno.land/r/REPLACE_ADDR/collatz" \
  -func Compute -args 27 ...

# view the leaderboard
gnokey query vm/qrender --data "gno.land/r/REPLACE_ADDR/collatz:"

# view the full hailstone sequence for 27
gnokey query vm/qrender --data "gno.land/r/REPLACE_ADDR/collatz:/27"
```
