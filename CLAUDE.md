# CLAUDE.md

This repository has a single, authoritative guide for agents: **[AGENTS.md](./AGENTS.md)**.
Read it before doing anything. The essentials:

- **Version everything.** Contracts live at `gno.land/{p,r}/moul/<name>/vN`.
  Breaking change ⇒ new `vN` directory, never edit a published version in place.
- **Keep the repo autonomous.** Local `p/moul` ↔ `r/moul` imports resolve via
  `gnowork.toml`; external `gno.land/*` deps are vendored under `vendor/`
  (`make deps`). Don't rely on `$GNOROOT/examples` for anything but stdlibs.
- **Keep the catalog honest.** After adding/removing a contract run `make gen`
  (updates `contracts.json` + the README table + every package README); CI fails
  if stale (`make check`).
- **Every package has a README.** It explains the package (hand-written, above
  the footer marker) and carries a repo link + disclaimer (generated footer, via
  `make readmes`). Packages under an `/x/` path get the stronger
  "highly experimental / potentially vibe-coded" disclaimer automatically. Full
  disclaimer: [DISCLAIMER.md](./DISCLAIMER.md).
- **Green before commit:** `make lint test` (needs `GNOROOT` = a gnolang/gno checkout).

## Commits

- Conventional, single-line: `feat(<name>): …`, `fix: …`, `chore(deps): …`.
- **Never** add Claude/AI co-author or `Co-Authored-By` trailers.
- Author: `Manfred Touron <94029+moul@users.noreply.github.com>`.
- **Never commit a compiled binary.** The maintenance CLI runs via
  `go tool gnocontracts <cmd>` (declared in `go.mod`); the Makefile wraps it.

## Handy

```sh
make help          # all targets
make test lint     # verify
make gen           # regenerate catalog after adding a contract
make sync          # drift vs the gnolang/gno monorepo
make publish NET=topaz CHECK=1
```

Everything else — layout, the `tools/` CLI, how to add a contract, the monorepo
drift workflow, CI invariants — is in [AGENTS.md](./AGENTS.md).
