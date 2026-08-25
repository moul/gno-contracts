# Luhn Checksum

> ⚠️ **Experimental — generated with no human supervision** by the daily MCP pipeline to exercise gno tooling. Not audited. See [r/moul/x/daily](https://github.com/moul/gno-contracts/blob/main/r/moul/x/daily/README.md).

---

Put a number in the path and the realm tells you whether its Luhn check digit is
right — and if not, what it should have been.

Demo of the [`p/moul/x/daily/luhn`](https://github.com/moul/gno-contracts/tree/main/p/moul/x/daily/luhn/v1)
library — validation, the check digit and the separator handling all come from
the package; this realm holds no checksum logic of its own. Read-only and
stateless, so `Render` is fully deterministic.

```
/r/moul/x/daily/luhndemo/v1                  → usage + worked samples
/r/moul/x/daily/luhndemo/v1:79927398713      → valid
/r/moul/x/daily/luhndemo/v1:79927398710      → invalid, suggests check digit 3
/r/moul/x/daily/luhndemo/v1:4539-1488-0343-6467 → separators are ignored
```

The samples on the root page are picked to show the two error classes Luhn
actually catches: a wrong digit, and two adjacent digits swapped.

Built for gno 0.9.
