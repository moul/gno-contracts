# AGENTS.md — working in moul/gno-contracts

This repository holds **moul's personal gno.land contracts** (`p/moul/*` packages
and `r/moul/*` realms). It is optimized so a human or a coding agent can build,
test, lint, and publish everything from a single clone. Read this file fully
before making changes.

## The three rules

1. **Everything is versioned.** Every contract path ends in an explicit version
   segment — `gno.land/{p,r}/moul/<name>/v1` (then `v2`, `v3`, …). There is *no*
   un-versioned contract, ever. A breaking change is a **new `vN` directory**,
   never an in-place edit of an existing published version.
2. **The repo is autonomous.** It builds with only a gno toolchain (`$GNOROOT`)
   plus what is in this repo. Local `gno.land/p/moul/*` imports resolve through
   the workspace (`gnowork.toml`); external `gno.land/*` deps are **vendored**
   under `vendor/` (committed). Never introduce a dependency that only resolves
   from `$GNOROOT/examples` — vendor it (`make deps`).
3. **The catalog is generated, keep it honest.** `contracts.json` and the README
   table are produced by the tools. After adding/removing a contract, run
   `make gen` and commit the result. CI fails if they are stale (`make check`).

## Repository map

```
p/moul/<name>/vN/       pure package   → gno.land/p/moul/<name>/vN
r/moul/<name>/vN/       realm          → gno.land/r/moul/<name>/vN
vendor/gno.land/...     vendored external deps (committed)
tools/gnocontracts/     Go maintenance CLI, run via `go tool gnocontracts` (see below)
contracts.json          catalog: source of truth for the README table + publish
gnowork.toml            empty workspace marker (enables local resolution)
Makefile                task entrypoints
.github/workflows/ci.yml  builds gno master, then test/lint/check
```

## Toolchain & environment

- `GNOROOT` must point at a `gnolang/gno` checkout (provides the gno binary's
  stdlibs). CI builds gno from `master`; locally, set it to your checkout.
- The gno version convention is `gno = "0.9"` in every `gnomod.toml`, built
  against gno **master** (the topaz-era API: `chain`, `chain/runtime`,
  `chain/banker`, `gno.land/p/nt/avl/v0`, …). State-mutating exported realm
  functions are crossing functions (first parameter `cur realm`).

## Common tasks

```sh
make help      # list targets
make test      # gno test every contract
make lint      # gno lint every contract
make deps      # vendor external gno.land deps into vendor/
make gen       # refresh contracts.json + README table  (run after add/remove)
make check     # verify the catalog is not stale (what CI runs)
make sync      # report drift vs the gnolang/gno monorepo
make publish NET=topaz CHECK=1   # dependency-ordered publish plan + on-chain status
```

## Adding a contract

1. Create `p/moul/<name>/v1/` or `r/moul/<name>/v1/` with a `gnomod.toml`:
   ```toml
   module = "gno.land/{p|r}/moul/<name>/v1"
   gno = "0.9"
   ```
2. Add sources + tests. Prefer table-driven tests; realms should have a `Render`.
3. If it imports an external `gno.land/*` package, run `make deps` to vendor it.
4. `make lint test` until green.
5. `make gen` to register it in `contracts.json` and the README table, then
   edit the contract's `description` (and `draft: true` if WIP) in
   `contracts.json` — these human fields are preserved across regenerations.
6. Commit.

## The maintenance CLI (`tools/gnocontracts`)

A dependency-free Go tool declared in `go.mod` (`tool` directive) and invoked as
`go tool gnocontracts <cmd>` — **never** built into a committed binary. Also
driven by the Makefile. Subcommands:

- `manifest` — scan the trees, reconcile `contracts.json` (preserves
  `description`, `draft`, `published`).
- `readme` — regenerate the README table from `contracts.json`.
- `gen` — `manifest` + `readme`.
- `check` — `gen` then fail on any diff (CI drift guard).
- `vendor` — copy external `gno.land/*` deps (transitively) into `vendor/`.
- `sync` — diff our versioned contracts against the (un-versioned) monorepo
  copies and report drift / new-here / monorepo-only.
- `publish` — topologically order contracts by dependency; with `-net`/`-check`,
  query the chain (`gnokey query vm/qfile`) and record upload status.

## Drift & monorepo relationship

Many of these contracts also exist in `gnolang/gno` under
`examples/gno.land/{p,r}/moul/*` **without** versioning. `make sync` compares
them so moul can (a) notice upstream changes to his contracts and (b) decide
when to cut a new `vN` here or bump a dependency. Treat the monorepo as an
upstream to reconcile *from*, deliberately — never auto-overwrite.

## Conventions

- **Commits:** conventional, single-line (`feat(hello): …`, `fix: …`,
  `chore(deps): vendor …`). Never add Claude/AI co-author trailers.
- **Commit author:** `Manfred Touron <94029+moul@users.noreply.github.com>`
  (the push-safe noreply identity).
- **Go tools:** stdlib only, no third-party deps (keeps the repo autonomous).
- **Never commit a compiled binary.** The CLI runs via `go tool gnocontracts`
  (declared in `go.mod`); there is no build artifact in the tree.
- **Never** hand-edit the region between the README table markers, or the
  generated fields of `contracts.json` (`pkgpath`, `dir`, `kind`, `name`,
  `version`, `deps`).

## Every package MUST have a README

Each package/realm directory ships a standalone `README.md` that:

1. **Explains the package** — what it is, what it does, minimal API/usage. This
   is hand-authored, ABOVE the generated footer marker.
2. **Links back to the repo** and **carries the disclaimer** — this lives in a
   generated managed block (between the `<!-- BEGIN/END GNOCONTRACTS FOOTER -->`
   markers). Do not hand-edit inside it; run `make readmes`.
3. **Experimental (`/x/`) packages** get the stronger disclaimer automatically:
   "Highly experimental — potentially vibe-coded", linking to
   [`DISCLAIMER.md`](./DISCLAIMER.md). Any package under an `/x/` path segment is
   treated as experimental/AI-assisted and not for production use.

`make readmes` creates a stub + footer for any package missing a README and
refreshes the footer everywhere; `make gen` runs it, and `make check` fails if a
package README is missing or its footer is stale. The full disclaimer is
[`DISCLAIMER.md`](./DISCLAIMER.md) (the long form); the per-package minimal
disclaimer links to it.

## CI invariants (must stay green)

`gno lint` + `gno test` pass for every contract; committed `vendor/` matches
`make deps`; `contracts.json` + README table + every package README match
`make gen` (enforced by `make check`).
