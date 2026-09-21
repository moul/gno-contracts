# AGENTS.md — working in moul/gno-contracts

This repository holds **moul's personal gno.land contracts** (`p/moul/*` packages
and `r/moul/*` realms). It is optimized so a human or a coding agent can build,
test, lint, and publish everything from a single clone. Read this file fully
before making changes.

## The three rules

1. **Everything is versioned, starting at `v0`; bump only on a compatibility
   change.** Every contract path ends in an explicit version segment —
   `gno.land/{p,r}/moul/<name>/v0` (then `v1`, `v2`, …). There is *no*
   un-versioned contract, ever, and **the version is always the LAST path
   element**: `gno.land/p/moul/ulist/lplist/v0`, never
   `gno.land/p/moul/ulist/v0/lplist`. That is the PACKAGE path; the directory
   is `p/moul/ulist/lplist` and carries no version at all.
   - **`v0` is the first version of any path**, per gno's own convention
     (gnolang/gno#5220): *initial, unaudited*. New contracts start there.
   - **The version lives in `gnomod.toml`, not in the directory name.**
     `p/moul/md/` declaring `module = "gno.land/p/moul/md/v1"` publishes to
     `gno.land/p/moul/md/v1`. The gno toolchain resolves a workspace import
     from the module line and ignores the directory path.
   - **Bump** with `gnopm bump <name>` for a **compatibility /
     breaking change**: removing, renaming, or changing the signature or
     on-chain behavior of an existing exported symbol, or changing storage
     layout / the backing data structure (e.g. swapping `avl` → `bptree`).
     Never make such a change in place on a published version, and **never
     create a `vN` directory or copy a package to bump it**: the copy is
     invisible to git, so the review diff of the change that most needs
     reviewing is a pile of added files with no content diff.
     `bump` rewrites the one line and pins the outgoing version in
     `gnomod.lock`; you then edit the files in place and git diffs them.
   - **Edit in place** for everything **non-breaking**: adding new
     exported functions, unit tests, comments, README/docs. (Test files and
     READMEs are not part of the deployed package, so they never change its
     on-chain hash; adding a function is backward-compatible.)
   - **A superseded version has no directory.** It is pinned in `gnomod.lock`
     to the commit that still holds it, rebuilt into the gitignored `.gnopm/`
     by `gnopm sync` (which `make lint`/`make test` do for you), and it is
     still linted, tested and listed in the catalog. Anything importing
     `.../md/v0` keeps resolving. See [`tools/gnopm`](./tools/gnopm).
   - **Mirrored `v0`s are frozen.** For the twelve packages that also live in
     `gnolang/gno` examples (see *Drift & monorepo relationship*), every `.gno`
     file and the `gnomod.toml` are a **byte-for-byte copy** of the monorepo's
     and are **never hand-edited** — not a comment, not a test. That is what lets
     `make sync` treat any diff as real upstream drift. Anything we want to
     change goes in a new `v1`. The only file we add is `README.md`, which is not
     part of the deployed package and is excluded from the drift comparison.
2. **The repo is autonomous.** It builds with only a gno toolchain (`$GNOROOT`)
   plus what is in this repo. Local `gno.land/p/moul/*` imports resolve through
   the workspace (`gnowork.toml`); external `gno.land/*` deps are **vendored**
   under `vendor/` (committed). Never introduce a dependency that only resolves
   from `$GNOROOT/examples` — vendor it (`make deps`).
3. **The catalog is generated on `main`, not in PRs.** `contracts.json`, the
   README table, per-package README footers, and `_assets/` graphs are all
   produced by the tools. **A PR carries only package SOURCE** — never run
   `make gen` or commit those generated files in a branch/PR. The `main`
   workflow regenerates them, refreshes on-chain status and commits the lot on
   `main` after every merge (and hourly); committing them in a PR only creates
   conflicts. (CI does **not** run `make check`, but it does reject a PR that
   carries a generated file: `gnocontracts guard-generated`.)

## Repository map

```
p/moul/<name>/          pure package   → gno.land/p/moul/<name>/vN
r/moul/<name>/          realm          → gno.land/r/moul/<name>/vN
                        (vN comes from gnomod.toml, not from the path)
vendor/gno.land/...     vendored external deps (committed)
tools/gnocontracts/     Go maintenance CLI, run via `go tool gnocontracts` (see below)
tools/gnopm/            versions, gnomod.lock and the .gnopm/ assembly
tools/internal/gnomod/  the gnomod.lock format, shared by both tools
contracts.json          catalog: source of truth for the README table + publish
gnomod.lock             where each version's source is (SOURCE, a PR carries it)
gnowork.toml            empty workspace marker (enables local resolution)
.gnopm/                 superseded versions, rebuilt from history (gitignored)
Makefile                task entrypoints
.github/workflows/    ci (the gate), pr (one bot comment + preview), main (regen)
.github/actions/      setup-gno, previews-sync, pr-comment — shared by those workflows
```

## Toolchain & environment

- `GNOROOT` must point at a `gnolang/gno` checkout (provides the gno binary's
  stdlibs). CI builds gno from `master`; locally, set it to your checkout.
- **The `gno` binary must be built from the SAME checkout `GNOROOT` names, and
  that checkout must be at least as new as `vendor/`.** Three revisions have to
  agree and nothing checks that they do. A binary older than the checkout fails
  with `function pubKeyAddress does not have a body but is not natively defined`;
  a checkout older than `vendor/` fails with `name SplitPkgSubPath not declared`
  from inside a vendored package. Neither message names the real problem. As of
  2026-09-19 the primary checkout `~/p/gh/gnolang/gno` sits on a feature branch
  behind master and `~/go/bin/gno` is older still, so a green run means building
  a matching binary from a master-tracking worktree and pointing both at it:

  ```sh
  cd <master-worktree> && go build -o /tmp/gnobin/gno ./gnovm/cmd/gno
  cd - && make test GNO=/tmp/gnobin/gno GNOROOT=<master-worktree>
  ```

  Verified 2026-09-19: 198 packages, 0 failures, with
  `GNOROOT=~/p/gh/gnolang/gno-merkleutil`.
- The gno version convention is `gno = "0.9"` in every `gnomod.toml`, built
  against gno **master** (the sapphire-era API: `chain`, `chain/runtime`,
  `chain/banker`, `gno.land/p/nt/avl/v0`, …). State-mutating exported realm
  functions are crossing functions (first parameter `cur realm`).

### Where gno differs from Go (these have each broken CI)

gno is close enough to Go that Go habits compile in your head and fail in CI.
The ones that have actually bitten this repo:

- **`avl/v0`'s `Get` returns ONE value**, not `(value, ok)`. A miss is a nil
  interface, so it is `v := t.Get(k); if v == nil { … }`. Writing
  `v, ok := t.Get(k)` is `assignment mismatch: 2 variables but Get returns 1
  value` — it turned `r/moul/x/daily/asciiart/v0` red. The comma-ok form IS
  right on the *type assertion* of the result: `p, ok := t.Get(k).(*poll)`.
- **`sort.Slice` does not exist.** gno's `sort` has `Sort(Interface)` and the
  `Search*` helpers only, so ordering needs an explicit `sort.Interface`. Break
  ties deterministically (e.g. on address) — a `Render` that reshuffles between
  identical calls is a bug, and gno map iteration order is unspecified, so never
  iterate a map to build output.
- **Every test function starts at block height 123; only realm state carries
  over.** `testing.SkipHeights` is RELATIVE, there is no `testing.Height` and no
  absolute setter, and a skip only moves the height *within* the test that called
  it: the next test starts back at 123 while package-level state (an avl tree, a
  cooldown map) keeps whatever the previous test wrote. So anything height-gated
  needs a fresh account per test, or its own skip, or it fails on the second test
  to touch it. Never assert an absolute height or a value derived from one, ask
  the realm (e.g. a `Day()` helper) instead. Measured 2026-09-19 against gno
  master while writing `r/moul/x/grc20wrapdemo/v0`; the previous claim here (that
  height carries over between tests) was wrong.
- **`testing.SetRealm` only governs the crossing calls made from the frame that
  called it.** Call it in a test helper that does not itself cross and it is
  silently ignored: the caller stays whoever it was, which is usually the realm's
  own address, and that surfaces much later as `cannot send transfer to self` or
  a balance credited to nobody. A helper that crosses right afterwards (claim,
  approve) DOES work, which is exactly what makes this hard to spot. Switch
  accounts INLINE in the test body. `testing.SkipHeights` in between is safe, it
  does not clear the actor (checked 2026-09-19).
- **`ufmt` supports NO width or padding flags.** `ufmt.Sprintf("%03d", 7)`
  returns `"7"`, not `"007"` — silently, with no error. This matters for avl
  keys: unpadded numeric keys sort `"0","1","10","11","2"`, so anything keyed
  that way silently loses insertion order past nine entries. Pad by hand (see
  `padIdx` in `r/moul/demo/importdemo/v0`).

- **`recover()` cannot catch a panic from a crossing call.** A panic raised
  across `cross(cur)` is a realm *abort*, and a `defer`/`recover()` in the
  caller never fires: the test just dies with `unexpected panic: <message>`.
  This holds even when the test is in the realm's own package. Assert a refusal
  with `uassert.AbortsWithMessage(t, cur, "msg", func() { F(cross(cur), …) })`
  (or `AbortsContains`) from `gno.land/p/nt/uassert/v0`, which is also the form
  this file ranks above a filetest. Check it is not a silent pass by breaking
  the expected message once and watching it fail.
- **A filetest's `// PKGPATH:` must end in a path element literally named
  `main`.** `gno.land/r/moul/x/plan9/nstest` fails to build with
  `package name "main" does not match path element "nstest"`; `…/plan9/main`
  works. Anything `println`ed before an abort is dropped, so an aborting
  filetest gets an `// Error:` block and no `// Output:` block at all.

When a new divergence costs a red CI, add it here: this file is pulled by the
daily build agent before every generation, so a line here stops the next repeat.

## Common tasks

```sh
make help      # list targets
make test      # gno test every contract
make lint      # gno lint every contract
make deps      # vendor external gno.land deps into vendor/
make gen       # refresh contracts.json + README table  (bot runs this on main; local preview only)
make check     # verify the catalog is not stale (used by the main regen bot, NOT PR CI)
make sync      # report drift vs the gnolang/gno monorepo
make publish NET=sapphire CHECK=1   # dependency-ordered publish plan + on-chain status
make publish NET=pearl CHECK=1      # …same, against the other testnet
```

### Networks

**`mainnet` — chain-id `gnoland-1`**, launched 2026-09-12T15:00:00Z from the
`chain/mainnet` tag (commit `9c8eb132e`). A fresh chain, not a hardfork of
betanet. `rpc.gno.land` / gnoweb at `gno.land`. It **replaced** the old `betanet`
row, which named the same endpoint with chain-id `gnoland1` — a different chain,
so that row probed mainnet under the wrong label and would have signed publishes
for a chain-id the node rejects.

Two things make mainnet unlike the testnets:

- **Publishing is not immediate.** The inert code-submission policy is on from
  block 1: a post-genesis `MsgAddPackage` parks until the funded gpao approvals
  oracle clears it. Budget for that; a publish that "succeeds" is queued, not live.
- **Paths there are permanent.** The `moul` namespace is registered at genesis,
  and nine of our mirrored `p/moul/*/v0` are already deployed as transitive deps
  of the genesis set (`addrset` `authz` `fifo` `helplink` `md` `mdtable` `once`
  `realmpath` `txlink`). Those nine are frozen upstream artifacts — never publish
  over them; changes go in a `v1` here. `dynreplacer`, `typeutil` and `ulist` are
  the three mirrors NOT at genesis.

### Publishing: keep the client at the chain's revision

`tools/gnopublish` builds against a **local gno checkout** — `go.mod` carries a
`replace github.com/gnolang/gno => ../../../../gnoland/gno`, so it silently
compiles against whatever revision that working tree happens to sit at. There is
no version pin to warn you.

When the chain is ahead of that checkout, the first symptom is an opaque amino
error from the account query, e.g. mainnet adding `vesting` to `std.BaseAccount`:

```
error: query account g1…: unknown JSON field "vesting" for type std.BaseAccount
```

Fix: move that checkout to the revision the chain runs — for mainnet the
`chain/mainnet` tag — and re-run. `gnopublish` now annotates this specific
failure with that instruction, and performs the account query **before**
prompting for the gnokey password, so a stale client costs nothing.

Two live testnets, both on gno `v1.0.0-rc.0` and interchangeable as publish
targets — `sapphire` (`sapphire-1`) and `pearl` (`pearl-1`). Each exposes the
same host pattern: `rpc.<net>.testnets.gno.land`, gnoweb at
`<net>.testnets.gno.land`, and an agent faucet at
`faucet-agent.<net>.testnets.gno.land` (`/fund` is POST-only; `/limits` reports
the grant and the per-address window — the bare root has no index route and
404s, which says nothing about the faucet being up).

The network list is **code-owned**: edit `defaultNetworks()` in
`tools/gnocontracts/model.go`. `manifest` reconciles `contracts.json` against
it, so the change lands via the `main` workflow — hand-editing the catalog
can't work, the `guard-generated` CI step rejects PRs that touch it.

## Adding a contract

1. Create `p/moul/<name>/` or `r/moul/<name>/` (**no `/v0` in the directory**)
   with a `gnomod.toml`:
   ```toml
   module = "gno.land/{p|r}/moul/<name>/v0"
   gno = "0.9"
   ```
   New contracts always start at `v0` (rule 1). The only paths that start at
   `v1` are successors to a `v0` the monorepo owns.
2. Add sources + tests. Prefer table-driven tests; realms should have a `Render`.
3. If it imports an external `gno.land/*` package, run `make deps` to vendor it.
4. `gnopm sync` to add it to `gnomod.lock`, then `make lint test` until green.
5. **Commit the new source files** (the contract directory) **and
   `gnomod.lock`**. The lock is source, not a generated artifact: CI checks it
   with `make verify`. Do **not** run `make gen` and do **not** stage
   `contracts.json`, `README.md`, or `_assets/` — the `main` workflow
   generates those after merge. (You can run `make gen` locally to
   preview the catalog, but revert it before committing.)
6. Commit + open the PR.

## Bumping a contract

```
gnopm bump <name>      # rewrites the module line, pins the old version
# ...edit the files in place...
make lint test
```

`<name>` is a directory, a module path, or any unambiguous part of one, so
`p/moul/md`, `gno.land/p/moul/md/v0` and `md` all work. `gnopm status` says
where things stand, `gnopm sync` fixes whatever is out of date.

Commit the source edit **and** `gnomod.lock` together. The directory never
moves and nothing is copied, so the diff is the compatibility change itself.

`bump` refuses to run when the package has uncommitted changes: it records the
commit that still holds the outgoing version, and a dirty directory would make
that record a lie. It also pins to a commit already on `origin/main` where it
can, because this repository squash-merges and a pin to a feature branch's HEAD
would dangle the moment the PR lands.

### Libraries vs. demos — split reusable logic into `p/` + `r/`

When a contract is **reusable logic** (a codec, algorithm, data structure,
utility — most `x/daily/*` ports fall here), don't ship it as a single realm.
Split it into two contracts:

- a **pure library** `p/moul/<…>/<name>/vN` — the reusable API as exported
  types/functions, with no realm-global state and no chain imports where they
  can be avoided (the caller supplies context such as the block height or the
  address). Unit-tested (table-driven).
- a **thin demo realm** `r/moul/<…>/<name>demo/vN` — imports the library, wires
  it to the chain (`runtime.ChainHeight()`, `unsafe.PreviousRealm()`, package-
  level state) and shows it off through `Render`. **No logic of its own.**

The two must **cross-reference each other** in both the package doc-comment and
the README: the library links to its demo ("Live demo: `r/…`"), the demo says it
is a demo of the library ("Demo of the `p/…` library"). Worked examples:
`p/moul/x/daily/b58` + `r/moul/x/daily/b58demo` (#53); `p/moul/x/daily/ratelimit`
+ `r/moul/x/daily/ratelimitdemo` (#50).

Only keep a lone realm when the contract is inherently a stateful app with
nothing reusable to extract.

> This convention grows from moul's PR feedback. When moul gives new guidance on
> how to structure a contract, record it **here** (and in `CLAUDE.md`) so the
> next contract follows it from the start — the contract-building agent rereads
> these files each time.

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
- `sync` — diff our contracts against the monorepo copy at the SAME path and
  report drift / ours / new-here / monorepo-only.
- `publish` — topologically order contracts by dependency; with `-net`/`-check`,
  query the chain (`gnokey query vm/qfile`) and record upload status.
- `status` — refresh that status for every network at once. A chain that does
  not answer is SKIPPED, not recorded as hosting nothing (see below).
- `pr` — everything CI needs about a pull request, from one diff: the sticky
  comment body, the `gh pr edit` label arguments, the realms to preview.
- `preview` — boot gnodev on the workspace and crawl the resulting gnoweb into
  a self-contained static tree. `-all` renders every package (`make site`); a
  `-changed` file list renders what a pull request touched plus every package
  that imports it (`make preview`). See *Previews* below.
- `guard-examples`, `guard-render`, `guard-generated` — the CI guards. They read
  `.gno` with `go/scanner`, so `// Output:` inside a string literal and an
  identifier like `printRender` no longer fool them (both did, as regexps).

## Drift & monorepo relationship

Twelve `p/moul/*` packages also live in `gnolang/gno` under
`examples/gno.land/p/moul/<name>/v0` — `addrset`, `authz`, `dynreplacer`,
`fifo`, `helplink`, `md`, `mdtable`, `once`, `realmpath`, `txlink`, `typeutil`,
`ulist`. Those paths ship in the **gnoland1 genesis set**, so their `v0` is
owned by the monorepo and frozen forever. There is no `r/moul/*` upstream at
all.

Our copy of each is a **byte-for-byte mirror at the same path**. `make sync`
compares them position-for-position:

- `[drift]` — the monorepo copy changed. Reconcile deliberately: re-sync the
  mirror, or cut a `v1` here if we want to diverge. Never auto-overwrite.
- `[ours]` — a version above the mirrored one (`addrset/v1`, `authz/v1`): our
  own successor, nothing upstream to compare against.
- `[new]` — the ~175 packages that exist only here.
- `[miss]` — upstream has a `p/moul/*` we do not carry yet.

Because the monorepo owns `v0` for those twelve, and only those twelve, a
version number is meaningful across both repos: `p/moul/addrset/v1` is the
second generation of a package whose first lives in `gnolang/gno`, while
`p/moul/x/daily/b58/v0` is a first cut that only ever existed here.

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

## Every realm MUST test its `Render` (example test)

A realm's `Render(path)` is user-facing output — lock it down with a gno
**example test** (`Example…` functions, gno's recent example-test feature). Put
it in a normal `_test.gno` **in the realm's package** so it calls `Render`
directly, no self-import (**especially demos**):

```gno
package foodemo

// ExampleRender pins the realm's Render output as a testable example.
func ExampleRender() {
	print(Render("")) // root; add more Example funcs for representative paths
	// Output:
	// …
}
```

This is **enforced by CI**: `make guard-render` (`gnocontracts guard-render`) fails
when an `r/` package declares `func Render` and no test ever calls it. Coverage
counts from a normal `*_test.gno` **or** a `*_filetest.gno`, and the call may be
bare (`Render(`) or qualified (`home.Render(`). `ignore = true` packages are
skipped. Five realms had shipped with a completely unexercised `Render` before
the guard existed.

Rules that make it actually run and verify:

- The **`// Output:` block is required** — an example with no `// Output:` is
  silently **skipped**. Its content must match `Render`'s output exactly
  (leading/trailing whitespace is trimmed).
- Use the builtin **`print(...)`** — its output is captured on stdout in tests,
  and it needs **no import** (prefer it over `fmt.Println` to keep the test file
  import-free). Trailing whitespace is trimmed, so the missing newline is fine.
- Cover the root plus a couple of argument paths (one `ExampleRender…` each).
- Keep output **deterministic**: tests run at a fixed chain height, but don't
  render wall-clock/random values.
- **Realm globals persist for the whole test binary, and examples run *after*
  every `Test`.** So an `ExampleRender` sees the state the tests left behind, and
  its pinned output silently depends on test ordering. Have the example **reset
  the state it renders** first (call the realm's `Reset`, or assign the globals
  back to their `init()` values from a helper — same package, so it's allowed).
  Likewise don't hardcode a generated id: take it from the constructor's return
  value, since it depends on how many objects earlier tests created.
- Validated by `gno test` on a **master** gno (what CI builds). Older gno
  binaries silently skip examples, so verify with a freshly built master gno
  (`go build -o /tmp/gno ./gnovm/cmd/gno` in your gno checkout) — a plain `ok`
  from a stale local `gno` does not prove the example ran.

Populating `// Output:`: run the example once with an empty `// Output:` and copy
the `got:` block the failure prints. Worked examples: the `x/daily/*demo` realms.

**Consecutive blank lines can't be pinned by an example.** gno (like Go)
**collapses consecutive blank lines** in a `// Output:` block, so any output with
two-or-more blank lines in a row (a lot of markdown `Render`s) will never match.
When that happens, don't use an example — assert the output in a normal `Test`
with `uassert.Equal(t, expected, got)` using a raw-string literal (backticks),
which preserves blank lines exactly, stays in-package, and needs no `fmt`. Worked
example: `p/moul/mdlist` `TestEntriesRendering`.

Order of preference: **example test** → **`Test` + `uassert.Equal`** (blank-line
or panic/error outputs) → **filetest** (`filetests/*_filetest.gno`, auto-populated
by `-update-golden-tests`; last resort, e.g. a package `main`/entrypoint).

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

A PR includes the **hand-authored top** of each new package's README (the
explanation above the footer marker). The generated footer, the root README
table, and the catalog are all produced on `main`: `make readmes` creates/
refreshes footers and `make gen` runs it, invoked by the `main` workflow after
merge — not in a PR. The full disclaimer is [`DISCLAIMER.md`](./DISCLAIMER.md)
(the long form); the per-package minimal disclaimer links to it.

## CI invariants (must stay green)

PR CI checks only **source**: `gno lint` + `gno test` pass for every contract,
and committed `vendor/` matches `make deps`. It does **not** run `make check` —
`contracts.json`, the README table, per-package footers and `_assets/` are
regenerated and committed on `main` by the `main` workflow.

### The four workflows

| workflow | when | what it owns |
|---|---|---|
| `ci` | push to main, every PR | the gate: `guard-generated`, `gnopm verify`, the tool tests, `make toolcheck guard-examples guard-render lint test` |
| `pr` | every PR event | **one** sticky comment, the path labels, and the published preview at `pr-<N>/` |
| `main` | push to main, hourly, manual | the single writer of `contracts.json`, the README table, package README footers, `_assets/`, and on-chain status |
| `gnopublish-ci` | PRs touching `tools/gnopublish/**` | that module only; it links the whole gno client stack and must not slow every PR |

Three composite actions carry what they share: `.github/actions/setup-gno`
(clone gno master outside the workspace, build the requested binaries, cached on
the upstream SHA, Go version from `tools/go.mod`), `.github/actions/previews-sync`
(rewrite one subfolder of the previews site and push, retrying when a parallel
job moved the branch) and `.github/actions/pr-comment` (upsert the one sticky
comment and delete any duplicate).

### Previews

Every package is browsable as gnoweb renders it, without a checkout:

| URL | What | Rebuilt |
|---|---|---|
| <https://moul.github.io/gno-contracts-previews/main/> | every package on `main` | every push to `main` |
| `…/pr-<N>/` | what pull request N changed, plus every package that imports it | every push to the PR |

Both come from `gnocontracts preview`, which boots **one** gnodev on the whole
workspace and crawls it. Three things about that are load-bearing:

1. **gnodev is given every package, not just the ones being rendered.** A package
   here is versioned in its `gnomod.toml`, not in its directory path, so gnodev
   cannot find `gno.land/p/moul/authz/v0` by walking to `p/moul/authz/v0`. Lazy
   loading makes the whole workspace cost the same as one package: 193 packages,
   node ready in 9s.
2. **`GNOROOT` is the stdlib-only view**, the same one `lint` and `test` use, so a
   preview resolves dependencies out of committed `vendor/` rather than out of
   whatever the gno checkout happens to hold.
3. **A changed pure package previews its dependents.** The reverse-import walk is
   transitive: touching `p/moul/md` renders every realm that renders markdown. The
   previous preview rendered nothing at all for a diff that touched no `r/`.

Bounds, because a realm may link as many pages as it likes: at most 25 packages on
a pull request (changed ones are never dropped, and the comment says how many
were), 10 render-argument pages per package, and never a `$state`, `$help&func=`,
`$download` or `:args$source` page. Without the argument budget one realm
(`romannumdemo`, one page per numeral) produced 4,065 of 5,437 pages and 220 MB of
323 MB on its own.

Every page is `noindex, nofollow`: each is a near-duplicate of a real gno.land
page, and gnoweb's own layout asks to be indexed.

The site lives in **[moul/gno-contracts-previews](https://github.com/moul/gno-contracts-previews)**,
not in this repository's `gh-pages`: the main snapshot is 103 MB rewritten on every
push, and this repository is one everybody clones. That branch is rewritten as a
single orphan commit each time, so the previews repository only ever holds the site
as it is now. Publishing needs the `PREVIEWS_DEPLOY_KEY` secret, the private half of
a write deploy key on that repository; a fork has no secrets, so it renders nothing
and is linked to nothing.

Locally: `make preview ARGS="./r/moul/home"` or `make site`, then serve the result
(`python3 -m http.server -d _site`). A previews link is always safe to click and
never a live chain: no signer, no transactions, no faucet, and every package shows
the state right after `init()`.

**One bot comment per PR**, marker `<!-- gnocontracts-pr -->`, rendered by
`gnocontracts pr`. It fits in three lines: counts, risk signals, preview link.
Everything per-package is inside a `<details>`. When adding a check, add a
*count* to the signal line or a *chip* to a table row, never a new bullet per
package: that is what made the old comment 45 lines long.

### On-chain status and unreachable chains

`make status` (and `publish -check`) probe every network with
`gnokey query vm/qfile`. A query to a chain that is **down** fails exactly like
a query for a package that was **never published**, and conflating the two used
to write "not uploaded" for all 193 packages of any network that happened to be
unreachable. So:

- each network is probed once with an HTTP `/status` call first, and a network
  that does not answer is skipped, keeping its last known values;
- a per-package query that fails for a transport reason leaves that entry alone;
- only a clean "not found" answer records an absence.

A skipped network keeps stale data rather than wrong data. The run says which
ones it skipped, and the `main` workflow logs a warning instead of failing.
