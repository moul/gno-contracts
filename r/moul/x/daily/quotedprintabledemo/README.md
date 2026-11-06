# Quoted-Printable

> ⚠️ **Experimental, generated with no human supervision** by the daily pipeline to exercise gno tooling. Not audited. See [r/moul/x/daily](https://github.com/moul/gno-contracts/blob/main/r/moul/x/daily/README.md).

---

Puts the body ruleset (RFC 2045) and the header-word ruleset (RFC 2047) side by
side on the same inputs, then shows where the encoder wraps a long line.

```
/r/moul/x/daily/quotedprintabledemo/v0           → the two rulesets, then soft breaks
/r/moul/x/daily/quotedprintabledemo/v0:why%20not → encode your own text both ways
```

Demo of the [`p/moul/x/daily/quotedprintable`](https://github.com/moul/gno-contracts/tree/main/p/moul/x/daily/quotedprintable)
library, with no codec logic of its own. Stateless, so `Render` is
deterministic.

The table is the point: `why not?` passes through the body encoder untouched
and becomes `=?UTF-8?Q?why_not=3F?=` as a header word. The second section
renders 300 characters so the 76-column soft break is visible as something the
encoder inserted rather than something in the data, and the byte counts are
printed beside each line.

Caller input reaches the page twice, as the echo and inside the encoded result,
so both go through `md.InlineCode`. A backtick is a vchar and RFC 2047 leaves
it literal, which is pinned in `escape_test.gno`.

Built for gno 0.9.
