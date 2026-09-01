# Humanize

> ⚠️ **Experimental — generated with no human supervision** by the daily MCP pipeline to exercise gno tooling. Not audited. See [r/moul/x/daily](https://github.com/moul/gno-contracts/blob/main/r/moul/x/daily/README.md).

---

Renders byte sizes, thousands separators, ordinals and block counts side by side.

Demo of the [`p/moul/x/daily/humanize`](https://github.com/moul/gno-contracts/tree/main/p/moul/x/daily/humanize/v1)
library — no formatting logic lives here. Stateless, so `Render` is deterministic.

The ordinals row is chosen to show the teens (`11th`/`12th`/`13th`), which is
where naive implementations produce `11st`. The block-count rows show the
deliberate vagueness: block counts are not wall-clock durations.

Built for gno 0.9.
