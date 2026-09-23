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
- **…and `Remove` returns TWO**, `(value, removed)`, which is the opposite rule on the
  neighbouring method of the same tree. `if !t.Remove(k)` is `multiple-value
  t.Remove(k) in single-value context`; write `if _, removed := t.Remove(k); !removed`.
  Caught by lint in `r/moul/faucet`. Knowing the `Get` rule is what makes this one land,
  so the two belong next to each other.
- **`sort.Slice` does not exist.** gno's `sort` has `Sort(Interface)` and the `Search*`
  helpers only, so ordering needs an explicit `sort.Interface`. Break ties
  deterministically (on address, say): a `Render` that reshuffles between identical calls
  is a bug, and gno map iteration order is unspecified, so never iterate a map to build
  output.
- **Every test function starts at block height 123; only realm state carries over.**
  `testing.SkipHeights` is RELATIVE, there is no `testing.Height` and no absolute setter,
  and a skip only moves the height *within* the test that called it: the next test starts
  back at 123 while package-level state (an avl tree, a cooldown map) keeps whatever the
  previous test wrote. So anything height-gated needs a fresh account per test, or its own
  skip, or it fails on the second test to touch it. Never assert an absolute height or a
  value derived from one, ask the realm instead (a `Day()` helper). Measured 2026-09-19
  against gno master while writing `r/moul/x/grc20wrapdemo`; the claim that stood here
  before, that height carries over between tests, was wrong.
- **`testing.SetRealm` only governs the crossing calls made from the frame that called
  it.** Call it in a test helper that does not itself cross and it is silently ignored:
  the caller stays whoever it was, usually the realm's own address, and that surfaces much
  later as `cannot send transfer to self` or a balance credited to nobody. A helper that
  crosses right afterwards (claim, approve) DOES work, which is exactly what makes this
  hard to spot. Switch accounts INLINE in the test body. `testing.SkipHeights` in between
  is safe, it does not clear the actor (checked 2026-09-19).
- **`ufmt` supports NO width or padding flags.** `ufmt.Sprintf("%03d", 7)` returns `"7"`,
  silently. That matters for avl keys: unpadded numeric keys sort `"0","1","10","11","2"`,
  so anything keyed that way loses insertion order past nine entries. Pad by hand
  (`padIdx` in `r/moul/demo/importdemo`).
- **`uassert.AbortsContains` takes a `func()`, not a `func(realm)`.** With the
  `func(realm)` form the helper does its own `cross(rlm)` first, which consumes the pending
  `testing.SetRealm`, so the abort under test runs with the realm itself as caller and
  every authorization assertion fails with `unauthorized` instead of the error you meant to
  pin. Use a no-arg closure that crosses with the outer `cur`, as `r/moul/x/wesh` and
  `r/moul/forge` do:
  `uassert.AbortsContains(t, cur, "stale ref", func() { SetRef(cross(cur), …) })`.
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
- **A read with no `cur realm` sees the CALLER as `unsafe.CurrentRealm()`, not itself.**
  Such a function is borrowed: gno opens no realm frame for it, so a plain read exported by
  one realm and called by another reports the caller's path. That is what makes a
  zero-argument helper on a shared realm possible at all
  (`config.TopBlock()`, `config.IsPaused()`), and it reverses the moment the function
  grows a `cur realm` parameter, at which point it silently starts reporting its own realm
  for every caller. Measured 2026-09-22 from `r/moul/config/v1`, called by a code realm at
  `gno.land/r/test/caller`: `CurrentRealm=gno.land/r/test/caller`,
  `PreviousRealm=gno.land/r/moul/config/v1`. A paired `…For(pkgPath)` variant is the
  escape hatch for crossing functions, and `r/moul/config/blocks_test.gno` pins the rule.
  Never branch on it for authorisation either way: it is `unsafe` for that reason.

When a new divergence costs a red CI, add it here. This file is pulled by the build agent
before every generation, so a line here stops the next repeat.

## Adding a contract

1. Create `p/moul/<name>/` or `r/moul/<name>/`, **no `/v0` in the directory**, with a
   `gnomod.toml`. A `p/` package is versioned and published, and never private:
   ```toml
   module = "gno.land/p/moul/<name>/v0"
   gno = "0.9"
   ```
   A realm is private by default, so that you can redeploy it at this path later instead
   of burning a `/v1`. `make guard-private` refuses one that says neither this nor why it
   has to stay importable, and after the first deploy neither can be changed:
   ```toml
   module = "gno.land/r/moul/<name>/v0"
   gno = "0.9"
   private = true
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

### `private = true` is the default for every `r/`, and the guard asks before you ship

A realm whose `gnomod.toml` says `private = true` can be **redeployed at the same
path by its original creator**, instead of being abandoned for a `vN+1`. Everything
else about it is a one-way door, so this is decided once, before the first publish.

Measured on `gnolang/gno@master` with the integration harness, 2026-09-22, not inferred:

| across a redeploy | |
|---|---|
| the code | replaced |
| coins at the realm address | **kept** (probe: 700000ugnot before and after) |
| every package-level variable | **wiped**, back to its initializer (probe: a counter at 3 read 0) |
| storage deposit | accumulates. Prior objects are not evicted and nothing can free them, so each redeploy is charged in full and refunds nothing |

And the constraints, from `checkGnomodConstraints` and `checkRedeployPermission` in
`gno.land/pkg/sdk/vm/keeper.go`:

- **Public cannot become private, private cannot become public.** Both are refused, so
  the realms already on chain can never convert either way.
- **Only `addpkg.creator` may redeploy.** Not the namespace owner, the original signer.
- **No other realm may import it**, hold a reference to its objects, or retain a value
  of a type it defines. The import is refused by the type checker (`ImportPrivateError`).
  The other two are a *runtime* panic out of `assertObjectIsPublic`, `cannot persist
  object from the private realm <path>`, so `gno lint` is blind to them and only a test
  that actually exercises the cross-realm call finds them. `r/moul/x/plan9/dev` is the
  worked example: it posts its own tree into `r/moul/x/plan9/ns`, lints clean as private,
  and panics on the first `gno test`.
- `private` is realm-only: a `p/` package declaring it is refused. `p/` is versioned and
  published, always, and that is the whole difference between the two trees.
- Reading it from outside is unaffected: `vm/qrender` and `vm/qeval` work normally.
- On mainnet a redeploy is a `MsgAddPackage`, so it **parks like any other** and waits
  for an approver. "Replaceable" is not "hot-patchable".

**So every new realm gets `private = true`, and one that must stay importable says why.**
The default is not a claim that replacing beats versioning in general. It is a claim about
which mistake is cheaper: a realm that shipped private and wanted to be imported is one
line and a `vN+1`, while a realm that shipped public and wanted a fix is a new path, a
migration, and coins stranded at the old address. The second is what `r/moul/faucet` got,
by two minutes.

The opt-out is a comment, and the reason is the point:

```toml
module = "gno.land/r/moul/x/plan9/ns/v0"
gno = "0.9"

# public: imported by r/moul/x/plan9/dev, which is what the pair is for
```

A comment rather than `private = false` because the gnomod field is `omitempty`: `false`
and absent serialize the same, so a reader could not tell a decision from an oversight.

`make guard-private` enforces it, and is part of `make guards`. It does not ask four kinds
of realm, because for them the question is not open: archived (`ignore = true`), mirrored
byte-for-byte from the monorepo, superseded (no directory), and **already live on mainnet
at that exact module path**, where the chain has answered and will not take another answer.

What the guard cannot see is whether the copy the chain holds matches the flag in the file.
`r/moul/faucet/v0` declares `private = true` and mainnet's copy at that path does not: the
deploy landed at 14:56:06Z on 2026-09-22 and the flag was committed at 14:58:25Z. The realm
is frozen public forever and the flag is decoration. Only the publish path can catch that
shape, and it does not yet.

The one thing that makes private genuinely safe is designing for the wipe: keep the durable
part in something a redeploy does not touch (coins at the address, or a local source of
truth you can push back) or accept losing it. `r/moul/home` does the first and says so in
its own gnomod.


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
  `tools` module where vet and test cover it.
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
| `pearl` | `pearl-1` | testnet, gno `v1.0.0-rc.0`. **The** testnet. |
| `staging` | `staging` | `rpc.staging.gno.land`. |

`sapphire` (`sapphire-1`) was the second testnet and is **retired**: its RPC host stopped
resolving on 2026-09-22 and it is gone for good. It is removed from `defaultNetworks()`
rather than kept with a warning, because a name in that list is a publish target and
`NET=sapphire` would have built a script against a dead endpoint.

pearl exposes `rpc.<net>.testnets.gno.land`, gnoweb at
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

### `make publish` is gnopm, and gnopm is the only publisher

`make publish KEY=<key> PKG=<substring>` asks gnopm what is live, parked or absent on the
chain the package paths point at, and runs `gnokey maketx addpkg` once per package in
dependency order, with your terminal attached. `PRINT=1` writes the commands out and runs
nothing. gnopm holds no key and signs nothing: gnokey does, and it prompts exactly as it
would if you had typed the command.

There used to be two other paths here, `gnocontracts publish`/`upload` and
`tools/gnopublish`. Both are gone. Anything that publishes goes through gnopm, so there is
one place where gas, fees, dependency order and chain discovery are decided, and one place
to fix when one of them is wrong.

Two things that path still gets right, and each one bit before:

- **Never pipe the plan into a shell.** gnokey reads its passphrase with
  `term.ReadPassword` on **fd 0** (`tm2/pkg/commands/utils.go`), so `gnopm publish -print | sh`
  hands gnokey a pipe as stdin and the prompt fails. gnopm running gnokey itself is the
  normal path; if you save `-print` output, run it as `sh <file>`.
- **gnopm discovers the chain from the package path**, so `gno.land/...` means **mainnet**
  unless told otherwise. There is no network name to typo into a different chain.

**Gas is a fixed cost plus a per-byte cost**, and sizing it from bytes alone is wrong rather
than merely tight. Over 464 successful mainnet `add_package` transactions the fit is
`gas ~= 3.8M + 1,285 * bytes`: every deployment pays to be parsed, type-checked and
initialised before the first source byte is charged for, and gas per byte ranges 989 to
16,435. gnopm sizes `12,000,000 + 2,600/byte` (v0.7.1), clamped to block `MaxGas`, with the
fee at 0.003 ugnot/gas against a chain floor of 0.001 (`auth/gasprice`). The flat
`1800/byte` it carried until then under-funded 37% of that history and killed a real
83-package run on a 4 KB package.

### On-chain status, and chains that do not answer

`make status` probes every network with `gnokey query vm/qfile`. A
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
