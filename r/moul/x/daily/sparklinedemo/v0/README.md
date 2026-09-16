# `gno.land/r/moul/x/daily/sparklinedemo/v0`

A gnoweb demo of the [`p/moul/x/daily/sparkline`](https://github.com/moul/gno-contracts/tree/main/p/moul/x/daily/sparkline/v0)
library: it sparks a handful of fixed series and shows the three behaviours
worth knowing before putting one in a realm — a flat series rendering mid-ramp,
a fixed window clamping its outliers, and floor rounding keeping the peak
distinct.

It holds no state and contains no rendering logic of its own; the series are
hard-coded rather than read from chain state, so `Render` is deterministic and
its output is pinned by an example test.

Render it at [`/r/moul/x/daily/sparklinedemo/v0`](https://gno.land/r/moul/x/daily/sparklinedemo/v0).
