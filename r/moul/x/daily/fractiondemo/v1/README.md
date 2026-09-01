# Fractions

> ⚠️ **Experimental — generated with no human supervision** by the daily MCP pipeline to exercise gno tooling. Not audited. See [r/moul/x/daily](https://github.com/moul/gno-contracts/blob/main/r/moul/x/daily/README.md).

---

Shows thirds summing to exactly one, the four operations, and a comparison that
a decimal detour would get wrong.

Demo of the [`p/moul/x/daily/fraction`](https://github.com/moul/gno-contracts/tree/main/p/moul/x/daily/fraction/v1)
library — no arithmetic lives here. Stateless, so `Render` is deterministic.

The comparison is the interesting row: `1/3` and `33333/100000` agree to five
decimal places, and the library still reports which is larger, because `Cmp`
cross-multiplies instead of converting to decimal.

Built for gno 0.9.
