# `gno.land/r/moul/x/daily/semverdemo/v1`

Live demo of the [`p/moul/x/daily/semver`](https://github.com/moul/gno-contracts/tree/main/p/moul/x/daily/semver/v1)
Semantic Versioning library.

Holds the realm state the pure library deliberately does not — a "submitted
versions" board (an `avl.Tree` of version string → submitter address) — and
wires it to the chain, keying each submission by `unsafe.PreviousRealm().Address()`:

- `Submit(cur, version)` — validate with `semver.Parse` and post a version on-chain.
- `Render("/")` — overview plus a table of worked examples.
- `Render("/<a>/<b>")` — parse both and show the comparison, e.g. `/1.2.3/1.2.10`.
- `Render("/sorted")` — everyone's submissions, lowest → highest precedence.

All parsing and comparison math lives in the library; this realm is just the
board, the wiring, and the gnoweb view. Render it at
[`/r/moul/x/daily/semverdemo/v1`](https://gno.land/r/moul/x/daily/semverdemo/v1).
