# CLAUDE.md

This repository has a single, authoritative guide for agents: **[AGENTS.md](./AGENTS.md)**.
Read it before doing anything. The essentials:

- **Version everything; bump only on a compatibility change.** Contracts live at
  `gno.land/{p,r}/moul/<name>/vN`. A **breaking change** — removing/renaming an
  exported symbol, changing its signature/behavior, or a storage/data-structure
  swap (e.g. `avl`→`bptree`) ⇒ **new `vN`** dir. **Non-breaking** work (new
  functions, unit tests, comments, docs) stays in place in the same `vN`.
- **Keep the repo autonomous.** Local `p/moul` ↔ `r/moul` imports resolve via
  `gnowork.toml`; external `gno.land/*` deps are vendored under `vendor/`
  (`make deps`). Don't rely on `$GNOROOT/examples` for anything but stdlibs.
- **PRs carry only source.** `contracts.json`, the README table, per-package
  README footers and `_assets/` are generated **on `main`** by the `regen`
  workflow after merge — never run `make gen` or commit those files in a PR
  (it only causes conflicts). CI runs no `make check`.
- **Every package has a README.** It explains the package (hand-written, above
  the footer marker) and carries a repo link + disclaimer (generated footer, via
  `make readmes`). Packages under an `/x/` path get the stronger
  "highly experimental / potentially vibe-coded" disclaimer automatically. Full
  disclaimer: [DISCLAIMER.md](./DISCLAIMER.md).
- **Reusable logic ⇒ split `p/` lib + `r/` demo.** A codec/algorithm/utility
  (most `x/daily/*` ports) ships as a pure, unit-tested library
  `p/moul/<…>/<name>` plus a thin demo realm `r/moul/<…>/<name>demo` that imports
  it and shows it via `Render`; the two cross-reference each other in comments +
  READMEs. Only a lone realm when it's a stateful app with nothing to extract.
  Details + examples in AGENTS.md.
- **Every realm tests its `Render`.** Prefer an in-package `ExampleRender()` (gno's
  example-test feature) that `print(Render(<path>))` (builtin — captured on
  stdout, no import) with a matching `// Output:` block (required — an example
  without it is skipped; deterministic). Verified by `gno test` on a **master** gno (CI does;
  a stale local gno silently skips examples). **If the output has consecutive
  blank lines** (examples collapse them), assert it with `uassert.Equal` in a
  normal `Test` instead; filetest last resort. Details in AGENTS.md.
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
