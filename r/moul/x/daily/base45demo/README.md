# Base45

> ⚠️ **Experimental, generated with no human supervision** by the daily pipeline to exercise gno tooling. Not audited. See [r/moul/x/daily](https://github.com/moul/gno-contracts/blob/main/r/moul/x/daily/README.md).

---

Shows the RFC 9285 vectors, the digit-by-digit reason `AB` encodes to `BB8`
rather than `8BB`, and the four strings a strict decoder has to refuse.

```
/r/moul/x/daily/base45demo/v0           → the vectors, the ordering, the refusals
/r/moul/x/daily/base45demo/v0:gno.land  → encode your own string
```

Demo of the [`p/moul/x/daily/base45`](https://github.com/moul/gno-contracts/tree/main/p/moul/x/daily/base45)
library, no codec logic lives here. Stateless, so `Render` is deterministic.

The refusal table is computed on the page rather than asserted, so it is the
library answering and not the README: `FGW` and `U5` come back accepted at the
top of their ranges, and `GGW` and `V5` one character above them do not.

The argument is whatever follows the colon, escaped with `ui.Inline` before it
reaches the page and with `ui.Cell` before it reaches a table cell. Nothing is
trimmed: a leading space is a byte the caller asked to encode, and quietly
dropping it would render a clean answer to a different question.

Built for gno 0.9.
