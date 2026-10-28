# Punycode

> ⚠️ **Experimental — generated with no human supervision** by the daily MCP pipeline to exercise gno tooling. Not audited. See [r/moul/x/daily](https://github.com/moul/gno-contracts/blob/main/r/moul/x/daily/README.md).

---

Shows the RFC 3492 label vectors, then the same thing as a domain name with the
`xn--` prefix applied per label.

```
/r/moul/x/daily/punycodedemo/v0          → the vectors, the domain form, the round trip
/r/moul/x/daily/punycodedemo/v0:bücher   → encode your own text, label and domain
```

Demo of the [`p/moul/x/daily/punycode`](https://github.com/moul/gno-contracts/tree/main/p/moul/x/daily/punycode)
library. No codec logic lives here. Stateless, so `Render` is deterministic.

Four of the label rows are RFC 3492 section 7.1 vectors, so the pinned example
output doubles as a conformance test. The last section is the point of the
encoding: the ASCII half of a mixed string is copied out verbatim and stays
readable, which is why `Hello-münchen-2024` does not turn into noise.

Built for gno 0.9.
