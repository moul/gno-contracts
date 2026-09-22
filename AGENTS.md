# AGENTS.md: working in moul/gno-contracts

moul's personal gno.land contracts, `p/moul/*` packages and `r/moul/*` realms, built,
tested, linted and published from a single clone. Read this file before changing anything.
[CLAUDE.md](./CLAUDE.md) is the one-line-per-rule index of it.

## The three rules

**1. The version is the `module` line, and it never lives in a directory name.**

Every package path ends in `/vN`: `gno.land/p/moul/ulist/lplist/v0`, never
`.../ulist/v0/lplist`. The directory is `p/moul/ulist/lplist` and carries no version at
all, so `p/moul/md/` declaring `module = "gno.land/p/moul/md/v1"` publishes to
`gno.land/p/moul/md/v1`. The toolchain resolves a workspace import from that line and
ignores the path.

- **New contracts start at `v0`**, gno's own convention for *initial, unaudited*
  ([gnolang/gno#5220](https://github.com/gnolang/gno/issues/5220)).
- **A breaking change is `gnopm bump <name>`**: removing or renaming an exported symbol,
  changing its signature or on-chain behavior, or swapping the backing storage
  (`avl` to `bptree`). `bump` rewrites the module line and pins the outgoing version in
  `gnomod.lock`; you then edit the files in place and git diffs the change.
  **Never create a `vN` directory and never copy a package to bump it.** git pairs
  nothing across a copy, so the review diff of the change that most needs reviewing
  becomes a pile of added files with no content diff. One port of 25 realms landed as
  +11,103 / 0 across 112 files that way.
- **Everything non-breaking edits the current version in place**: new exported functions,
  tests, comments, docs. Tests and READMEs are not part of the deployed package, so they
  never change its on-chain hash.
- **A superseded version has no directory.** It is pinned in `gnomod.lock` to a commit
  that still holds it and rebuilt into the gitignored `.gnopm/`, so anything importing
  `.../md/v0` still resolves, lints and tests. See [gnopm](https://github.com/moul/gnopm).
- **The one unversioned path is `r/moul/home`.** gnoweb serves `gno.land/u/<username>` by
  calling `Render("")` on the realm at exactly `/r/<username>/home`
  (`gno.land/pkg/gnoweb/handler_http.go`, `GetUserView`: built by string concatenation,
  with no version resolution anywhere in the lookup), so a `/v0` would publish where
  `/u/moul` never looks. The bare module line is an interface with gnoweb, which is why
  `gnopm bump` refuses the package: there is no `/vN` to increment. It versions inside
  instead, content in mutable storage and `private = true` in `gnomod.toml` so the code
  can be replaced in place. Do not generalise this without an external consumer that
  hard-codes the path.
- **The twelve mirrored `v0` are frozen.** For the packages that also live in
  `gnolang/gno` examples (see *Drift*), every `.gno` file and the `gnomod.toml` is a
  byte-for-byte copy of the monorepo's and is **never hand-edited**, not a comment, not a
  test. That is what lets `make sync` treat any diff as real upstream drift. Changes go
  in a new `v1`. `README.md` is the one file we add, and it is excluded from the compare.

**2. The repo is autonomous.** It builds with a gno toolchain (`$GNOROOT`, stdlibs only)
plus what is committed here. Local `gno.land/{p,r}/moul/*` imports resolve through the
workspace (`gnowork.toml`); external `gno.land/*` deps are vendored under `vendor/`.
Never introduce a dependency that only resolves from `$GNOROOT/examples`: vendor it with
`make deps`.

**3. A pull request carries only source**, plus `gnomod.lock` when a version changed.
`contracts.json`, the README contracts table, per-package README footers and `_assets/`
graphs are written on `main` by the `main` workflow after every merge and hourly. Never
run `make gen` in a branch: it only creates a conflict, and CI's `guard-generated` step
rejects a pull request that carries one. (CI does not run `make check`.)

## Repository map

```
p/moul/<name>/          package   -> gno.land/p/moul/<name>/vN  (vN from gnomod.toml)
r/moul/<name>/          realm     -> gno.land/r/moul/<name>/vN
vendor/gno.land/...     vendored external deps (committed)
tools/gnocontracts/     the maintenance CLI: go -C tools tool gnocontracts help
tools/gnohome/          Go companion driving r/moul/home
tools/gnopublish/       the simulation-based publisher (its own module)
contracts.json          catalog, generated on main
gnomod.lock             where each version's source is (SOURCE, a PR carries it)
gnowork.toml            workspace marker (enables local resolution)
.gnopm/                 superseded versions, rebuilt from history (gitignored)
.gnoroot-view/          stdlib-only image of GNOROOT (gitignored, see below)
Makefile                one line per target; `make help` groups them
.github/workflows/      ci (the gate), pr (comment + preview), main (regen)
.github/actions/        setup-gno, previews-sync, pr-comment
```

## Toolchain and environment

`GNOROOT` must point at a `gnolang/gno` checkout. CI builds gno from `master`. Every
`gnomod.toml` declares `gno = "0.9"`, built against master (the sapphire-era API:
`chain`, `chain/runtime`, `chain/banker`, `gno.land/p/nt/avl/v0`). State-mutating
exported realm functions are crossing functions, first parameter `cur realm`.

`make help` lists every target, grouped. `make lint test` is the gate; add
`PKG=<substring>` to narrow any of them to one package.

**Nothing reads `$GNOROOT` directly.** `gnocontracts gno` builds `.gnoroot-view/`, a
symlink image of the checkout whose `examples/` is empty, and points the toolchain at
that. gno resolves a `gno.land/*` import from `GNOROOT/examples` before anywhere else, so
without the view every lint, test and preview would silently pick up whatever the
monorepo checkout held that day rather than the copy committed under `vendor/`.

### Where gno differs from Go (each of these has broken CI)

- **`avl/v0`'s `Get` returns ONE value**, not `(value, ok)`. A miss is a nil interface:
  `v := t.Get(k); if v == nil { … }`. `v, ok := t.Get(k)` is `assignment mismatch: 2
  variables but Get returns 1 value`, and it turned `r/moul/x/daily/asciiart` red. The
  comma-ok form *is* right on the type assertion: `p, ok := t.Get(k).(*poll)`.
- **`sort.Slice` does not exist.** gno's `sort` has `Sort(Interface)` and the `Search*`
  helpers only, so ordering needs an explicit `sort.Interface`. Break ties
  deterministically (on address, say): a `Render` that reshuffles between identical calls
  is a bug, and gno map iteration order is unspecified, so never iterate a map to build
  output.
- **`testing.SkipHeights` is RELATIVE and there is no `testing.Height`.** No absolute
  height setter exists, so tests drive the height forward from wherever the previous test
  left it and never assert an absolute height or anything derived from one. Ask the realm
  instead (a `Day()` helper).
- **`ufmt` supports NO width or padding flags.** `ufmt.Sprintf("%03d", 7)` returns `"7"`,
  silently. That matters for avl keys: unpadded numeric keys sort `"0","1","10","11","2"`,
  so anything keyed that way loses insertion order past nine entries. Pad by hand
  (`padIdx` in `r/moul/demo/importdemo`).
- **`recover()` cannot catch a panic from a crossing call.** A panic raised across
  `cross(cur)` is a realm abort and a `defer`/`recover()` in the caller never fires, even
  when the test is in the realm's own package: the test dies with
  `unexpected panic: <message>`. Assert a refusal with
  `uassert.AbortsWithMessage(t, cur, "msg", func() { F(cross(cur), …) })` (or
  `AbortsContains`) from `gno.land/p/nt/uassert/v0`. Break the expected message once and
  watch it fail, or you cannot tell it from a silent pass.
- **A filetest's `// PKGPATH:` must end in a path element literally named `main`.**
  `gno.land/r/moul/x/plan9/nstest` fails to build with `package name "main" does not
  match path element "nstest"`; `…/plan9/main` works. Anything `println`ed before an
  abort is dropped, so an aborting filetest gets an `// Error:` block and no `// Output:`.

When a new divergence costs a red CI, add it here. This file is pulled by the build agent
before every generation, so a line here stops the next repeat.

## Adding a contract

1. Create `p/moul/<name>/` or `r/moul/<name>/`, **no `/v0` in the directory**, with a
   `gnomod.toml`:
   ```toml
   module = "gno.land/{p|r}/moul/<name>/v0"
   gno = "0.9"
   ```
2. Add sources and tests. Table-driven; realms need a `Render`.
3. `make deps` if it imports an external `gno.land/*` package.
4. `gnopm sync` to record it in `gnomod.lock`, then `make lint test` until green.
5. Commit the contract directory **and `gnomod.lock`**. Do not stage `contracts.json`,
   the root `README.md` or `_assets/` (rule 3). `make gen` previews the catalog locally;
   revert it before committing.

## Bumping a contract

```sh
gnopm bump <name>      # rewrites the module line, pins the old version
# ...edit the files in place...
make lint test
```

`<name>` is a directory, a module path, or any unambiguous part of one, so `p/moul/md`,
`gno.land/p/moul/md/v0` and `md` all work. `gnopm status` says where things stand,
`gnopm sync` fixes whatever is out of date. Commit the source edit and `gnomod.lock`
together: the directory never moves and nothing is copied, so the diff is the
compatibility change itself.

`bump` refuses to run on a package with uncommitted changes, because it records the
commit that still holds the outgoing version and a dirty directory would make that record
a lie. It pins to a commit already on `origin/main` where it can: this repository
squash-merges, so a pin to a feature branch's HEAD would dangle the moment it lands.

### Reusable logic splits into a `p/` library and an `r/` demo

A codec, algorithm, data structure or utility (most `x/daily/*` ports) is never a single
realm. It is:

- a **pure library** `p/moul/<…>/<name>`: the reusable API, no realm-global state, no
  chain imports where they can be avoided (the caller supplies the height, the address).
  Unit-tested, table-driven.
- a **thin demo realm** `r/moul/<…>/<name>demo`: imports the library, wires it to the
  chain (`runtime.ChainHeight()`, `unsafe.PreviousRealm()`, package-level state) and
  shows it through `Render`. **No logic of its own.**

The two cross-reference each other in both the package doc comment and the README: the
library links to its demo ("Live demo: `r/…`"), the demo says what it demonstrates
("Demo of the `p/…` library"). Worked examples: `p/moul/x/daily/b58` +
`r/moul/x/daily/b58demo` (#53), `p/moul/x/daily/ratelimit` + `…/ratelimitdemo` (#50).

Keep a lone realm only when the contract is inherently a stateful app with nothing
reusable to extract.

> This convention grows from moul's pull request feedback. When moul gives new guidance on
> how to structure a contract, record it **here**, because the contract-building agent
> rereads this file every time.

### Go companions live in `tools/<name>/`

A contract driven from a laptop (content pushed from local files, a generated payload, a
state dump) ships a small Go program at **`tools/<name>/`**, registered in the `tool`
block of `tools/go.mod` and run as `go -C tools tool <name>`. Worked example:
`tools/gnohome`, which drives `r/moul/home`.

Beside the contract would read better and is **not possible**. There is no Go module at
the repository root and there cannot be one: the root holds `vendor/gno.land`, and Go
treats a `vendor/` in a module root as Go vendoring, refusing to build and deleting what
it did not put there (the comment at the top of `tools/go.mod`). So `tools/` is the only
module covering ordinary packages, and anything outside it is built by nothing: `go vet`
and `go test` refuse it with *"directory prefix ... does not contain main module"*, and
CI, which runs `go -C tools vet ./...` and `go -C tools test ./...`, never sees it. A
companion placed beside its contract is silently untested, which is how `gnohome` spent
one pull request orphaned.

Rules that keep a companion small and safe:

- **Standard library only.** No `gnoclient`, no cgo, no third `go.mod`. Read the chain
  over plain JSON-RPC `abci_query`, about 60 lines, and the companion stays inside the
  `tools` module where vet and test cover it. (`tools/gnopublish` is the counter-example:
  it links the full gno client stack, so it had to become a separate module.)
- **Print transactions, never sign them.** Emit `gnokey maketx …` commands to review and
  paste. A companion holds no key and broadcasts nothing, so it can never surprise
  anyone. Name moul's key `moul` in what it emits.
- **Mirror, and say so.** Anything duplicated from the realm (slug rules, reserved names,
  a default template) carries a comment naming the `.gno` file it mirrors, and a Go test
  pinning the two to the same behaviour.
- **Table-driven tests, no network.** The chain-facing code is one function returning a
  string; test the parsing, not the transport.
- **Cross-link it** from the contract's README, since it no longer sits in the same
  directory. The gno toolchain ignores it: package discovery only finds directories
  holding a `gnomod.toml`, and `tools/` has none.

## Every realm MUST test its `Render`

A realm's `Render(path)` is its whole public surface, and a `Render` whose output varies
is a consensus bug. Lock it down with a gno example test, in a normal `_test.gno` **in
the realm's package** so it calls `Render` directly with no self-import (especially
demos):

```gno
package foodemo

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render("")) // root; add more Example funcs for representative paths
	// Output:
	// …
}
```

Enforced by `make guard-render`, which fails when an `r/` package declares `func Render`
and no test ever calls it. Coverage counts from a `*_test.gno` or a `*_filetest.gno`, and
the call may be bare (`Render(`) or qualified (`home.Render(`); `ignore = true` packages
are skipped. Five realms had shipped with a completely unexercised `Render` before the
guard existed.

What makes it actually run and verify:

- **The `// Output:` block is required.** An example without one is silently skipped.
  Its content must match exactly, leading and trailing whitespace trimmed.
  `make guard-examples` fails on a missing block.
- **Use the builtin `print(...)`.** It is captured on stdout in tests and needs no import,
  which keeps the test file import-free.
- **Cover the root plus a couple of argument paths**, one `ExampleRender…` each.
- **Keep the output deterministic.** Tests run at a fixed height; never render a
  wall-clock or random value.
- **Realm globals persist for the whole test binary, and examples run after every
  `Test`.** So an `ExampleRender` sees the state the tests left and its pinned output
  silently depends on their order. Reset the state it renders first (call the realm's
  `Reset`, or assign the globals back to their `init()` values from a helper: same
  package, so it is allowed). Likewise never hardcode a generated id, take it from the
  constructor's return value.
- **Only a master gno validates examples.** An older binary skips them, so `make test`
  runs `make toolcheck` first: a canary package whose pinned output is deliberately wrong,
  which must fail. If it passes, the toolchain is blind to examples and everything green
  here means nothing.

To populate `// Output:`, run the example once with the block empty and copy the `got:`
block the failure prints. Worked examples: the `x/daily/*demo` realms.

**Two consecutive blank lines can never be pinned by an example.** gno collapses them in
an `// Output:` block, like Go, and a lot of markdown `Render`s produce them. Assert those
in a normal `Test` with `uassert.Equal(t, expected, got)` and a backtick literal, which
preserves blank lines exactly, stays in-package and needs no `fmt`. Worked example:
`p/moul/mdlist` `TestEntriesRendering`.

Order of preference: **example test**, then **`Test` + `uassert.Equal`** (blank-line or
aborting output), then **filetest** (`filetests/*_filetest.gno`, auto-populated by
`-update-golden-tests`; last resort, such as a package `main`).

## A package README must say something, or not exist

The rule is not "every package has a README". It is that **a README which exists must say
something true and useful**. A placeholder is worse than nothing, because the package then
looks documented and the real text never gets written: this repo shipped 28 READMEs whose
entire content was `_TODO: describe this package._` plus boilerplate.

In order of preference:

1. **A good README**: what the package is, the minimal API, and the thing a reader cannot
   get from the source. Why it exists, what it is *not* for, what is unimplemented, which
   trap it avoids. If it is an unimplemented API sketch, say so in the first line.
2. **A minimal accurate one.** One true sentence is a perfectly good README.
3. **No README at all.** Legal, and `make guard-readmes LIST=1` lists these: undocumented,
   and visibly so.

Never a placeholder. `make guard-readmes` (in `make test` and in PR CI) fails on
TODO / TBD / FIXME / WIP / "coming soon" in the hand-authored region, on a README that is
nothing but its title and the footer, and on a body under 20 characters.

Everything hand-authored goes **above** the footer marker
(`<!-- BEGIN/END GNOCONTRACTS FOOTER -->`), which carries the repo link, the dependency
graph, the provenance line and the disclaimer. Do not hand-edit inside it; run
`make readmes`, which will not invent a README for a package with no catalog description.
Packages under an `/x/` path get the stronger "highly experimental, potentially
vibe-coded" disclaimer automatically. Full text: [DISCLAIMER.md](./DISCLAIMER.md).

## Drift and the monorepo relationship

Twelve `p/moul/*` packages also live in `gnolang/gno` under
`examples/gno.land/p/moul/<name>/v0`: `addrset`, `authz`, `dynreplacer`, `fifo`,
`helplink`, `md`, `mdtable`, `once`, `realmpath`, `txlink`, `typeutil`, `ulist`. Those
paths ship in the gnoland1 genesis set, so their `v0` is owned by the monorepo and frozen
forever. There is no `r/moul/*` upstream at all.

Our copy of each is a byte-for-byte mirror at the same path, and `make sync` compares them
position for position:

| | |
|---|---|
| `[drift]` | the monorepo copy changed. Reconcile deliberately: re-sync the mirror, or cut a `v1` to diverge. Never auto-overwrite. |
| `[ours]` | a version above the mirrored one (`addrset/v1`, `authz/v1`): our own successor, nothing upstream to compare against. |
| `[new]` | the ~175 packages that exist only here. |
| `[miss]` | upstream has a `p/moul/*` we do not carry yet. |

Because the monorepo owns `v0` for those twelve and only those twelve, a version number is
meaningful across both repos: `p/moul/addrset/v1` is the second generation of a package
whose first lives in `gnolang/gno`, while `p/moul/x/daily/b58/v0` only ever existed here.

## Publishing

### The networks

| name | chain-id | notes |
|---|---|---|
| `mainnet` | `gnoland-1` | `rpc.gno.land`, gnoweb at `gno.land`. Launched 2026-09-12T15:00:00Z from the `chain/mainnet` tag (commit `9c8eb132e`): a fresh chain, not a hardfork of betanet. |
| `pearl` | `pearl-1` | testnet, gno `v1.0.0-rc.0`. The default testnet. |
| `sapphire` | `sapphire-1` | testnet, same build. **On 2026-09-22 `rpc.sapphire.testnets.gno.land` had no DNS record at all**; re-check before sending anything to it. |
| `staging` | `staging` | `rpc.staging.gno.land`. |

Both testnets expose the same host pattern: `rpc.<net>.testnets.gno.land`, gnoweb at
`<net>.testnets.gno.land`, and an agent faucet at `faucet-agent.<net>.testnets.gno.land`
(`/fund` is POST-only; `/limits` reports the grant and the per-address window; the bare
root has no index route and 404s, which says nothing about the faucet being up).

The list is **code-owned**: edit `defaultNetworks()` in `tools/gnocontracts/model.go`.
`manifest` reconciles `contracts.json` against it on `main`. Hand-editing the catalog
cannot work, `guard-generated` rejects a pull request that touches it.

Two things make mainnet unlike the testnets:

- **Publishing is not immediate.** The inert code-submission policy has been on since
  block 1: a post-genesis `MsgAddPackage` parks until the funded gpao approvals oracle
  clears it. A publish that "succeeds" is queued, not live.
- **Paths there are permanent.** The `moul` namespace is registered at genesis, and nine
  of the mirrored `p/moul/*/v0` are already deployed as transitive deps of the genesis set
  (`addrset` `authz` `fifo` `helplink` `md` `mdtable` `once` `realmpath` `txlink`). Those
  nine are frozen upstream artifacts: never publish over them, changes go in a `v1` here.
  `dynreplacer`, `typeutil` and `ulist` are the three mirrors not at genesis.

### `make upload` writes a script, it does not sign

`make upload NET=<net> KEY=<key> PKG=<substring>` asks gnopm what is live, parked or
absent on that chain and writes dependency-ordered `gnokey maketx addpkg` commands to
`.cache/publish.sh`. Read it, then re-run with `YES=1`. Nothing leaves the machine until
then: gnopm never signs and never broadcasts.

Three things about that path are deliberate, and each one bit:

- **The script is run from a file, never piped.** gnokey reads its passphrase with
  `term.ReadPassword` on **fd 0** (`tm2/pkg/commands/utils.go`), so the `gnopm publish | sh`
  form gnopm's own help suggests hands gnokey a pipe as stdin and the prompt fails.
  `sh <file>` leaves stdin the terminal.
- **An unknown `NET=` is an error.** gnopm discovers the chain from the package path, so
  `gno.land/...` means **mainnet** unless told otherwise. This used to be a `$(shell)`,
  which cannot fail a make run: a typo'd network name expanded to nothing and produced a
  mainnet broadcast script.
- **A failed run leaves no script**, so `sh .cache/publish.sh` can never replay a stale
  plan aimed at a different chain.

gnopm sizes gas at a flat 1800 gas/byte and the fee at 0.01 ugnot/gas. Measured mainnet
`addpkg` history is 1,014 to 1,781 gas/byte, so that is a ceiling just above the observed
maximum, and a ceiling is not charged.

### `make upload-sim`: gnopublish, and keeping it at the chain's revision

`tools/gnopublish` is the older path, kept because it sizes gas from a **real simulation**
rather than an estimate and can merge every package into one transaction. Reach for it
when a package's `init()` work makes the flat estimate wrong.

It builds against a **local gno checkout**: its `go.mod` carries a
`replace github.com/gnolang/gno => ../../../../gnoland/gno`, so it silently compiles
against whatever revision that tree sits at, with no pin to warn you. When the chain is
ahead, the first symptom is an opaque amino error from the account query, such as mainnet
adding `vesting` to `std.BaseAccount`:

```
error: query account g1…: unknown JSON field "vesting" for type std.BaseAccount
```

Move that checkout to the revision the chain runs (for mainnet, the `chain/mainnet` tag)
and re-run. `gnopublish` annotates this specific failure with that instruction, and does
the account query **before** prompting for the gnokey password, so a stale client costs
nothing.

### On-chain status, and chains that do not answer

`make status` (and `publish -check`) probe every network with `gnokey query vm/qfile`. A
query to a chain that is **down** fails exactly like a query for a package that was
**never published**, and conflating the two used to write "not uploaded" for all 193
packages of any unreachable network. So each network is probed once with an HTTP
`/status` call first and skipped if it does not answer, a per-package query that fails for
a transport reason leaves that entry alone, and only a clean "not found" records an
absence. A skipped network keeps stale data rather than wrong data; the run says which
ones it skipped and the `main` workflow warns instead of failing.

## The tools

`go -C tools tool gnocontracts help` lists every subcommand; each one carries its
reasoning as a doc comment. The Makefile is a thin wrapper, one line per target, so a flag
belongs on the tool and not in a recipe. The ones worth knowing about by name:

- `gno lint | test | fmt | toolcheck | list`: the toolchain runner. It materializes the
  pinned versions, builds `.gnoroot-view/`, enumerates every non-archived package
  (archived ones must be filtered here: the toolchain skips an `ignore = true` module for
  `lint` but builds it anyway for a `test` that names it) and runs `gno` over the lot,
  eight at a time by default (`-j`).
- `sync`: drift against the monorepo copy at the same path.
- `pr`: everything CI needs from one diff, the sticky comment body, the `gh pr edit` label
  arguments, the realms to preview.
- `preview`: boot gnodev on the workspace and crawl the resulting gnoweb into a
  self-contained static tree.
- `guard-examples`, `guard-render`, `guard-readmes`, `guard-generated`: the CI guards.
  They read `.gno` with `go/scanner`, so an `// Output:` inside a string literal and an
  identifier like `printRender` no longer fool them (both did, as regexps).

Go tools here are **standard library only** and never built into a committed binary.

## CI

PR CI checks only source: `gno lint` and `gno test` pass for every contract, and committed
`vendor/` matches `make deps`. It does not run `make check` (rule 3).

| workflow | when | what it owns |
|---|---|---|
| `ci` | push to main, every pull request | the gate: `guard-generated`, `gnopm verify`, the tool tests, `make guards lint test` |
| `pr` | pull request opened / pushed / reopened | **one** sticky comment, the path labels, the published preview at `pr-<N>/` |
| `main` | push to main, hourly, manual | the single writer of `contracts.json`, the README table, README footers, `_assets/`, and on-chain status |
| `gnopublish-ci` | pull requests touching `tools/gnopublish/**` | that module only, because it links the whole gno client stack and must not slow every pull request |

**One bot comment per pull request**, marker `<!-- gnocontracts-pr -->`, rendered by
`gnocontracts pr`. It fits in three lines: counts, risk signals, preview link, everything
per-package inside a `<details>`. When adding a check, add a *count* to the signal line or
a *chip* to a table row, never a new bullet per package: that is what made the old comment
45 lines long.

Every package is also browsable as gnoweb renders it, without a checkout:
<https://moul.github.io/gno-contracts-previews/main/> for `main` and `…/pr-<N>/` for a
pull request, linked from its comment. Locally `make preview ARGS="./r/moul/home"` or
`make site`, then serve the result (`python3 -m http.server -d _site`). A previews link is
never a live chain: no signer, no transactions, no faucet, and every package shows the
state right after `init()`.

How the workflows, the three composite actions and the previews site work, and the traps
in each: [`.github/README.md`](./.github/README.md).

## Conventions

- **Commits**: conventional, single line (`feat(hello): …`, `fix: …`,
  `chore(deps): vendor …`). Never a Claude or AI co-author trailer.
- **Author**: `Manfred Touron <94029+moul@users.noreply.github.com>`, the push-safe
  noreply identity.
- **Never hand-edit** the region between the README table markers, or the generated fields
  of `contracts.json` (`pkgpath`, `dir`, `kind`, `name`, `version`, `deps`).
