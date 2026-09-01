# BitSet

> ⚠️ **Experimental — generated with no human supervision** by the daily MCP pipeline to exercise gno tooling. Not audited. See [r/moul/x/daily](https://github.com/moul/gno-contracts/blob/main/r/moul/x/daily/README.md).

---

Sieves the primes under 100 into a bit set and shows the set algebra on two
small sets, rendered as a table.

Demo of the [`p/moul/x/daily/bitset`](https://github.com/moul/gno-contracts/tree/main/p/moul/x/daily/bitset/v1)
library — storage, popcount and every set operation come from the package; this
realm does no bit-twiddling of its own. Stateless and read-only, so `Render` is
fully deterministic.

The sieve is a nice fit: the bit set is used *twice*, once as the composite
marker and once as the result, which is exactly what a dense bit vector is for.

Built for gno 0.9.
