# AGENTS.md: working in moul/gno-contracts

moul's personal gno.land contracts, `p/moul/*` packages and `r/moul/*` realms, built,
tested, linted and published from a single clone. Read this file before changing anything.
[CLAUDE.md](./CLAUDE.md) is the one-line-per-rule index of it.

**This file is how to work in this repository. [EFFECTIVE_GNO.md](./EFFECTIVE_GNO.md) is how
to write a contract**: which structure to store something in and what it costs, which package
renders a table, who the caller is, what to do about money. When a task is "build X", read
that one first and this one for the mechanics. When you learn a routing decision (this
question, that package), it goes there; when you learn a repository rule or a toolchain trap,
it goes here.

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
`make deps`. A package that lives only on a chain and in no `examples/` (GnoSwap's
`r/gnoswap/*` is the case that forced this) is vendored with `make deps-chain`, which
falls back to `vm/qfile` over RPC for exactly those. `examples/` still wins whenever it
has the package, so the two sources can never disagree about one. **`make bump-deps`
wipes `vendor/` and re-reads `examples/` only**, so it drops the chain-sourced packages:
run `make deps-chain` after it.

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
  `testing.SkipHeights` is RELATIVE; `testing.SetHeight` is the absolute setter, and it
  moves backwards as happily as forwards. There is no `testing.Height` READER: ask the
  chain with `runtime.ChainHeight()`. Either way the move lands only *within* the test that
  made it: the next test starts back at 123 while package-level state (an avl tree, a
  cooldown map) keeps whatever the previous test wrote. So anything height-gated needs a
  fresh account per test, or its own skip, or it fails on the second test to touch it.
  Never assert an absolute height you did not set, nor a value derived from one; ask the
  realm instead (a `Day()` helper). Measured 2026-09-19 against gno master while writing
  `r/moul/x/grc20wrapdemo` (the claim that stood here before, that height carries over
  between tests, was wrong) and corrected 2026-09-28 while writing `r/moul/x/moultest`,
  where "no absolute setter" turned out to be wrong too: `SetHeight` has been in
  `gnovm/tests/stdlibs/testing` all along.
- **The block CLOCK resets the same way, and it starts in 2009.** `time.Now()` in a realm
  is the block timestamp, and in a test it is **1234567890** (2009-02-13) at the top of
  every test function, exactly as height is 123. `testing.SkipHeights(10)` moves it 50s, so
  the test machine runs 5s blocks. The trap is a realm that stores a timestamp: build state
  in a test at a hand-picked "realistic" unix second (1700000000, say) and every later call
  reading `time.Now()` sees a clock fifteen years BEHIND the state it is being asked about,
  which surfaces as a time-went-backwards error from whatever does the arithmetic rather
  than as anything about tests. Drive the pure helpers with an explicit `at` argument and
  any constant you like; anchor anything that reaches `time.Now()` at `time.Now()`. Measured
  2026-09-28 against gno master while writing `r/moul/x/games/idle`.
- **The BANK does not carry over between test functions, though realm state does.** A
  balance issued in one test is gone in the next, while the package-level counters that
  recorded issuing it are not, so a realm's own view and the chain's can be made to
  disagree by nothing more than a test boundary. `r/moul/x/moultest` renders
  `issued: 1000000` beside `circulating: 0` for exactly this reason. Assert balances in
  the test that created them, and assert DELTAS rather than totals.
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
- **A `p/` package can neither DECLARE nor TEST a crossing function.** `func F(cur realm,
  ...)` in a non-realm package fails to build with `crossing function (realm first argument)
  declared in non-realm package`, and renaming it is no help: a realm first argument must be
  called `cur`, and `cur` in a `p/` is refused. Thread it later instead, `func F(_ int, rlm
  realm, ...)`, which is the shape `p/nt/grc20`'s tellers already use. Testing one from the
  package that declares it is impossible too: anything calling `rlm.Previous()` (minting a
  banker, reading the caller) dies with `frame not found: cannot seek beyond origin caller
  override`, because a `p/` test has no realm frame to walk. Exercise it from a realm's
  tests. Both hit while writing `p/moul/x/envelope`, 2026-09-28.
- **`banker.SendCoins`'s refusal panics with an `address`, not a string**, so
  `uassert.PanicsContains` reports `recover: unsupported type` and reads nothing. The message
  is built as `"..." + b.pkgAddr + "..."`, and in gno a string concatenated with a named
  string type takes that type. Catch it with a hand-written `recover()` carrying a
  `case address:` arm. Anything panicking with a value derived from an `address`, a
  `chain.Coin` denom or any other named string has the same shape.
- **`BankerTypeOriginSend` is gated on WHO entered the realm, not on how deep you are.**
  `NewBanker` requires `rlm.Previous().IsUserCall()`, and `Realm.IsUserCall` is literally
  `r.pkgPath == ""` (`gnovm/stdlibs/chain/runtime/frame.gno`). So passing `cur` down through
  your own helpers is fine (measured at three nested calls, through a function value and
  through a closure), while a realm called BY another realm cannot forward the envelope, and
  `maketx run` cannot reach a payable function at all. There is a second, unrelated
  `IsUserCall` in `chain/runtime/native.go` that DOES count frames; it is not on this path,
  and reading it instead cost a package doc that had to be rewritten.
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

- **Standard library only, for a companion.** No `gnoclient`, no cgo, no second module.
  Read the chain over plain JSON-RPC `abci_query`, about 60 lines, and the companion stays
  inside the `tools` module where vet and test cover it. This is a rule about
  `tools/<name>/`, **not about the `tools` module as a whole**: `tools/go.mod` requires
  `moul.io/gnopm`, and `tools/gnocontracts` imports `gnopm/pkg/gnomodlock` in `model.go`
  and `report_lock.go` on purpose, because the lock format has exactly one owner.
- **Never hold key material, and always keep a print path.** A companion emits the
  `gnokey maketx …` commands, naming moul's key `moul`. Signing itself is allowed and two
  companions do it: `gnohome tx -run` and `gnoblog` shell out to gnokey with the terminal
  attached, so gnokey holds the key and prompts for a passphrase the process never sees.
  Both write the same document and script first, so a half-finished run is reproducible by
  hand, and both default to printing. **What is forbidden is a process that could sign
  without being asked, or that ever sees a passphrase.** (Corrected 2026-09-29: this rule
  read "print transactions, never sign them", which the two companions it governs had
  already outgrown.)
- **Mirror, and say so.** Anything duplicated from the realm (slug rules, reserved names,
  a default template) carries a comment naming the `.gno` file it mirrors, and a Go test
  pinning the two to the same behaviour.
- **Table-driven tests, no network, and transport separated from parsing.** Keep the
  decoding in functions a test can call with a literal, so the tests never dial anything.
  Not "one function returning a string": `gnohome` and `gnoblog` both have a
  `fetchManifest` plus separate `qeval` and `abciQuery` helpers, which is the shape that
  actually survives.
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

## A realm that renders a caller's string MUST escape it

`make guard-untrusted-render` fails when a realm declares `Render`, takes a
string through a crossing function, and never calls `ui.Inline` / `ui.Cell` /
`sanitize.*`. Anything a caller typed and the realm stored is attacker-controlled
markdown: a link, an image, a table that breaks its own column, a bidi run that
reverses the sentence around it.

Wrap it once, at the call site that builds the markdown:

| helper | for |
|---|---|
| `ui.Inline(s)` | a sentence, a list item, a link title |
| `ui.Cell(s)` | a table cell, which must not open a new column |

If every stored string is validated at write time (one letter, an enum, a
semver, a charset-checked word), say so in the file instead:

```gno
// untrusted-render: every stored word is checked against the a-z charset at write time
```

The reason has a 20-character floor, because "n/a" answers nothing.

**Why a guard and not a review.** A public package path is immutable:
`AddPackage` refuses a path already occupied unless the live package is private,
so a realm that ships an unescaped `Render` keeps it forever and the only fix is
a new version at a new path. This is a pre-deploy gate or it is nothing. It was
a convention until 2026-09-22 and the convention lost: `r/moul/x/reaper` rendered
a caller's note body raw one PR after 25 other realms were ported to `ui.*`.

**The baseline is not an allowlist.**
`tools/gnocontracts/untrusted-render-baseline.txt` lists the 54 realms that were
already live when the guard landed. They cannot be fixed in place, so the guard
grandfathers them and gates the 55th. An entry leaves the file when the realm
ships a fixed version, and a stale entry is itself a failure: it would silence a
realm nobody is watching any more. Do not add to it by hand to quiet a failure,
that is what the opt-out is for.

## A markdown table is `ui.NewTable`, and `make guard-tables` enforces it

The single most repeated mistake in this repository's history: **102 files built a markdown
table by concatenating pipes**, and the package that tells everyone else not to,
`p/moul/pilot`, is one of them. Present tense, because it cannot be fixed: `329 of the 331`
contracts in the catalog are live on mainnet, `p/moul/pilot/v0` among them, and a public
package path is immutable. That is the whole argument for the guard.

Four things a hand-rolled table gets wrong, every time, none of them visible in a diff:

| | |
|---|---|
| a cell containing a pipe | silently opens a column nobody asked for, which is the cheapest way for a caller's string to rewrite the page around it |
| a row shorter than the header | silently drops its data instead of padding |
| an empty table | renders as a header with no body, instead of a sentence |
| the separator row | has to match the header count, and nothing checks it |

[`p/moul/kit/ui`](./p/moul/kit/ui)'s `Table` does all four.

`make guard-tables` detects **the separator row**, and only that, because it is the one part
of a GFM table that cannot be anything else: a run of dashes and pipes is a table header or
it is nothing. A bare `"| a | b |"` is genuinely ambiguous with prose, so it is not matched,
and the cost of that choice is a table assembled without a separator, which does not render
anyway.

It is a **ratchet over a baseline**: 100 packages recorded the day it landed, a package not
listed may not start, and a listed package that stops must leave the file or it hides the
next one. **Nearly all 100 are permanent**, for the reason above: their `Render` can never be
replaced at that path, so they are fixed in a `vN+1` and its importers, or not at all. This
guard buys nothing retroactively. It is a **pre-deploy** gate and only that.

> Learned the expensive way while writing it: `p/moul/pilot`'s `Render` was rewritten through
> `ui.NewTable`, `ui.Addr` and `num.GNOTf`, green, with its pinned `TestRender` updated, before
> `gnopm publish -print` said `8 live, nothing to do` and `gnopie INSPECT
> gno.land/p/moul/pilot/v0` came back with 12,728 bytes of storage on mainnet. The edit was
> reverted. **Ask the chain before editing anything, not after**, and remember that
> `r/moul/pilot` is public *and* documented as the one realm that must never be replaceable,
> so even a `p/moul/pilot/v1` would have no consumer able to adopt it.

The opt-out is for dashes that are not a table:

```gno
// handrolled-table: ASCII art, the dashes are a cow's horn, no table here
```

20-character floor on the reason, and an opted-out package leaves the baseline entirely, so
one package is never answered for by two mechanisms. The opt-out is read from **every** file
including tests, while the separator is detected only outside them: asymmetric on purpose,
because a package whose production source is already live can never be edited again, so its
test file is the only place a true opt-out can still be written. `p/moul/x/daily/cowsay` is
that case, and it is the first one.

Five packages are exempt in code because emitting a separator correctly is what they are for:
`kit/ui`, `mdtable`, `md`, `mdlist`, `template`.

## When to spend a Copilot code review, and when not to

**A Copilot code review costs about 76 AI credits, measured.** GitHub publishes 13 as the
model multiplier; the billing page charges roughly six times that. The measurement wins.

From the AI usage page's per-model breakdown, **2026-10-01**:

| | |
|---|---|
| plan | Copilot **Pro** |
| included | **1,500 AI credits a month**, resets the 1st |
| used | **1,211 of 1,500 (81%)**, on the **first day of the cycle** |
| of which | **1,210.74 is the Code Review model.** Essentially all of it |
| additional usage | **$0.00 of $0, NOT ENABLED** *(superseded: a $100 budget was enabled later the same day, see below)* |
| credit price | $0.01 |

Divide by the **16 Copilot reviews** requested that day (#274 x1, #289 x6, #295 x8, #296 x1,
and zero in any other repository) and a review is `1210.74 / 16 =` **~75.7 credits, about
$0.76**.

Three things follow, and the third is the one that actually matters.

**1. The Pro allowance is 1,500, not 300.** The 300 figure is the older premium-request unit.

**2. The failure mode was silence, not a bill.** With additional usage disabled, running out
simply **stopped** code review until the reset. **That changed the same day**: a $100 budget
is now enabled, so the total is ~11,500 credits, about 152 reviews a month, and the stop moves
to $100 rather than to zero. The reasoning below is what the budget was sized against. What this policy protects
is not money, which is capped at zero by construction, but the ability to get a review at the
moment one is worth having. On 2026-10-01 that was 289 credits, **under four reviews**, with
31 days to go.

**3. Re-reviews are the cost.** Fourteen of those sixteen reviews were third and later passes
on two pull requests. **Choosing which pull requests deserve a review would have saved nothing
on the day that spent the month's budget.** Capping passes per pull request is what saves it:
the first review, plus one after the findings are fixed. Beyond that, read the diff yourself.

At ~76 credits the whole allowance is **twenty reviews a month**. This repository opens ~215
pull requests a month, so reviewing all of them is not nine times the budget, it is eighty
times it.

So the rule is one sentence, and it falls out of this repository's central fact rather than
out of restraint:

> **Review exactly what is about to become permanent.**

331 of the 333 contracts in the catalog are live on mainnet, and a public package path is
immutable. A finding against a package that is **already live** cannot be acted on in place:
it needs a new version at a new path and every importer moved, which is a human decision a
review does not unblock. A package **not yet live** is one merge from being frozen forever,
and that is the only moment a review changes the outcome.

**Two other triggers**, each there because of a counterexample rather than for symmetry.

**A change to `.github/copilot-instructions.md` or `.github/instructions/`.** A wrong
instruction does not produce one wrong finding, it produces wrong findings on every later
review until somebody notices, which is a permanence of its own.

**A change to a non-test Go source under `tools/`, or a workflow.** (`_test.go` is excluded:
a test is where the bad shape is written on purpose.) This policy used to skip tooling on the grounds
that it has tests, has CI, and is fixable any time. The first two are true and the third made
it look cheap to drop. Then #296's review returned four findings and **every one was in
tooling or docs**: a markdown escaper that let a contributor put a live link in the hub issue,
a `gh api --paginate` that silently dropped every page but the first, a workflow that would
fail on any fork, and an index carrying a rule an earlier review had already disproved. None
of that is caught by tests, because none of it was wrong in a way anybody had thought to
test.

`make review-advice BASE=origin/main` answers it, reading `contracts.json` rather than the
chain, and prints the reason. It is **advice and never a gate**: it exits 0 and a human or an
agent decides.

```
REVIEW

why:
  - gno.land/p/moul/kit/index/v0 is NOT yet live on mainnet: this is the last
    moment a finding can be acted on in place

cost if requested: ~76 AI credits (measured) of 1500 included plus a $100
additional-usage budget, so about 151 reviews a month in total.

  gh pr edit <N> --add-reviewer @copilot
```

### What it costs, with the budget moul enabled on 2026-10-01

1,500 included credits, plus a **$100 additional-usage budget** at $0.01 a credit, is 11,500
credits a month: **about 152 reviews**.

Backtested over the last 60 merged pull requests, scaled to this repository's ~215 a month at
1.5 passes each:

| rule set | PRs | reviews/mo | overage |
|---|--:|--:|--:|
| permanence + config | 6/60 | 32 | **$9** |
| **+ tooling (what ships)** | **17/60** | **91** | **$54** |
| + every `.gno` pull request | 39/60 | 210 | $144, **over** |

So tooling is affordable and every `.gno` change is not, which is the line drawn above. The
two-pass cap is what keeps the picking from being undone: it is **not** a cost rule any more,
it is that the third and later passes on #289 and #295 were 14 of 16 reviews that day and
found proportionally much less than the first two.

### How many passes, and why the answer is not one number

Two arguments here look contradictory and **both are right**.

Fourteen of the sixteen passes across #289 and #295 spent a month's budget in a day, which
says cap it. And **passes two to five on #289 each found one to three more real defects**, all
in a package one merge from frozen: a copied `Index` that splits its counter from its tree,
every tag link dead, an untested global storage cap. Five extra passes cost ~380 credits,
about $3.80; any one of those defects shipped would have cost a new version at a new path.

What separates them is the thing the triage already asks: **whether a miss is recoverable.**

| the diff is | passes |
|---|---|
| a package **not yet live** | keep re-requesting after each fix until a pass adds nothing. A miss is permanent |
| tooling, a workflow, the config | **two**: the first, and one after the fixes land. A miss is fixable next week |

`make review-advice` prints whichever applies, because it already knows which case it is.

Two things it still does not do, deliberately. It does not look at diff size, because a
one-line change to an unpublished package is exactly as permanent as a thousand-line one. And
it does not review every `.gno` pull request, because at ~76 credits a review that is about
$144 a month against a $100 budget.
## Copilot code review, and the log that makes it better

The house rules live where GitHub already reads them:

| file | scope |
|---|---|
| `.github/copilot-instructions.md` | repo-wide |
| `.github/instructions/gno.instructions.md` | `**/*.gno` |
| `.github/instructions/go.instructions.md` | `tools/**/*.go` |

Request a review with `gh pr edit <N> --add-reviewer @copilot`, or the Copilot entry under
Reviewers. Automatic review is a **repository ruleset**, not a workflow. No secret, no Actions
minutes for the review itself, nothing metered per run.

Custom instructions are read from the **head branch**, so a pull request can test its own
instruction changes.

**Verify the effort, never assume the default held.** The account default is not what
reliably runs: on 2026-10-01 it was switched to Lite, the review on #312 at 19:00:02 ran
**Lite**, and two reviews on #311 at 19:00:34 and 19:10:06 ran **Balanced** anyway. Something
per-pull-request beats it, and the effort cannot be chosen from `gh` at all. Every review
reports its own level (`**Review effort:** Lite`), and `copilot-log` now records it, so a
cost figure derived from the log is no longer an average over an unknown mix.

**Every review is digested into [#280](https://github.com/moul/gno-contracts/issues/280)** by
`copilot-review-log.yml` (an hourly sweep, because a run triggered by Copilot's review waits
for an approval nothing can give it) plus `gnocontracts copilot-log`, one entry per finding,
"Previously missed" ones included, with three
boxes: real, false positive, or a finding about the knowledge base. The false-positive box
asks **which line of the instructions produced it**, and that is the whole design: a wrong
finding here is not noise to be endured, it is a defect in a file in this repository with a
line number.

**Answering a pass**: reply on each thread (`Confirmed and fixed in <sha>`, or why it is a
false positive), then resolve it. A re-review resolves a thread only when its anchored lines
changed, so a fix that landed in another file stays open until you resolve it by hand. A
"Previously missed" finding has no thread at all: answer it in one PR comment.

It works. The first review this repository ever got returned three findings, all three
against the instructions file that had just been added, each with file and line evidence, and
all three were real. Two of them were also findings about *this* file, and are why the
Go-companion rules above now say "never hold key material" rather than "never sign".

## `gnovet`: our own rules, and the loop that writes them

**A code review costs ~76 AI credits and finds a defect once. A rule costs nothing and
finds it every time.** `make gnovet` is where the second kind lives, and its defining property
is where the rules come from:

> Every rule here was a **finding first**. Something noticed a real defect in real code in
> this repository, the defect was fixed, and then the shape of it was written down so the next
> instance is caught for free, forever.

```
review finds it  ->  fix it  ->  write the rule  ->  never pay for it twice
```

A rule carries its provenance in the source. `Finding` names the pull request and the review
comment it came from, so a reader can go and check the original argument instead of taking the
rule on faith, and a rule that turns out to be wrong can be traced back to the reasoning that
produced it. **`make gnovet ARGS=-rules` prints all of them with that citation.** A rule
without one does not compile past the test suite.

### It paid for itself on the first run

Three rules, seeded from the #289 review and the storage benchmark. Pointed at the tree they
found **seven more instances of the two bugs Copilot had found once**, in packages nobody had
reviewed, plus the 93 `avl` imports we already knew about:

| rule | found | the one that stings |
|---|--:|---|
| `ceil-div-overflow` | 5 | `p/moul/kit/store/store.gno:287` has the identical `(n + size - 1) / size` I had just fixed in `kit/index` |
| `slice-inplace-remove` | 2 | `p/moul/x/daily/orderedmap`, which is a data structure whose whole job is this |
| `avl-in-new-code` | 93 | the ecosystem default, at 2,029 B/entry against a map's 153 |

**All seven are on live, immutable paths and none can be fixed in place.** That is not a
disappointment, it is the argument: the rule is a pre-deploy gate, and these shipped before it
existed.

Two more on 2026-10-01, each a shape review had found and the tree still carried:

| rule | found | the one that stings |
|---|--:|---|
| `page-offset-overflow` | 6, one already bounded | `p/moul/kit/store/store.gno:266`, the same unbounded `(page - 1) * size` #289 fixed in `kit/index`, and #311 found a third time |
| `placeholder-path` | 6 | three live daily realms linking to `/r/REPLACE_ADDR/...`, a generator token nobody substituted |

### Adding one

1. **Fix the defect first.** A rule for a bug still in the tree is a baseline row, not a rule.
2. Add a `Rule` to `tools/gnovet/rules.go` with `What`, `Why` (in gno terms, on this chain,
   with the number if there is one), `Fix`, and `Finding` citing the review.
3. Ship a `Bad` that fires and a `Good` that does not. The test suite asserts both, which is
   the only thing that stops a rule from quietly matching nothing after a refactor.
4. `make gnovet-update`, and read the new rows before committing them.

Use `f.Code` for anything matching an expression: comments and string contents are blanked
there, so a rule looking for `append(` does not match a doc comment explaining the rule, which
is the trap a regexp over raw source falls into in a repository whose comments discuss its own
lints. Use `f.Literal` (comments blanked, strings kept) for what genuinely lives in a string,
such as a rendered link, and `f.Raw` only for import paths.

The opt-out is `//gnovet:ignore <rule-id> <why>`, 20-character floor, on the line or the one
above it.

### Why it is a separate package

`tools/gnovet` imports nothing from this repository: the engine takes a directory, the rules
read source text. If it ever becomes useful to anybody else it lifts out as a module without a
rewrite. That is deliberate, and it is **not yet a promise**: these rules were learned from one
repository's mistakes and have been run against one repository's code.

## The audit patterns: somebody else's rules, on our contracts

`gnolang/gno` ships an audit pattern harness at `misc/audit-pattern-harness`: ten finding
families distilled from real audit work, each with a vulnerable fixture, a fixed fixture,
and a scanner that must flag the first and leave the second alone. Upstream runs it against
those fixtures, which proves the rules still fire. **Nothing in the ecosystem runs them
against real contracts.** `make audit-patterns` does.

It is a **ratchet**, not a pass/fail. `tools/gnocontracts/audit-pattern-baseline.txt`
records a count per (rule, package):

| | |
|---|---|
| a count goes up, or a new pair appears | **fail.** Read the line. |
| a count goes down, or a pair disappears | **fail**, asking to be re-recorded (`make audit-patterns-update`), so a fix cannot be quietly undone |
| everything at baseline | pass |

260 hits across 131 rows the day the guard landed. A baseline row is **not** a statement
that the code is fine; it is a statement that the hit predates the guard, and the backlog is
exactly that file. The families and why each is a finding:
[EFFECTIVE_GNO.md § 5.7](./EFFECTIVE_GNO.md#57-the-anti-pattern-list).

Three scoping decisions, each one stated in the code rather than discovered later:

- **Eight of the ten rules are scanned in `r/` only.** That is upstream's own framing: its
  expected records title them "accepted by a realm" and "returned from a realm", and its
  fixtures are realms. A `p/` iterator taking a callback (`avl.Tree.Iterate`, `store.Each`,
  `fp.Map`) and a `p/` constructor returning a pointer are those packages doing their job,
  and flagging them buried 96 real rows under them. `current_guard` and
  `interface_realm_param` stay tree-wide on purpose.
- **Test files are skipped**, the same line `guard-untrusted-render` draws: a test is not
  the deployed surface and its `cur.Previous()` is the author's own. The mirror scans every
  `.gno` because upstream's fixture package *is* its test, so the filter lives on our side.
- **The rules are a MIRROR, not an import.** Upstream's package is `internal/` inside a
  module of its own, so nothing reaches it. `tools/auditpattern/run.go` carries the rule
  functions and the `go/scanner` source reader byte for byte, with the upstream commit and
  the file's SHA256 in its header, and `audit-patterns -drift <gnoroot>` re-hashes the
  original. A mirror nobody verifies is a fork with a misleading comment on top. **Do not
  hand-edit it; re-mirror.** The real fix is an upstream pull request exporting the package.

CI runs it as its **own workflow** (`.github/workflows/audit-patterns.yml`), not a step in
`ci`: it needs no gno toolchain, so it answers in seconds where `ci` takes minutes, and a
separate check name is what makes "the security scan is red" legible in the pull request
list. The drift check there is a `::warning::` rather than a failure, because upstream
moving is not the pull request author's doing; the weekly scheduled run is what makes sure
somebody sees it.

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
| `onyx` | `onyx-1` | testnet, gno `v1.0.0-rc.0`. **The** testnet. |
| `staging` | `staging` | `rpc.staging.gno.land`. |

`pearl` (`pearl-1`) and `sapphire` (`sapphire-1`) were the testnets before it and are both
**retired**, with the same signature each time: the RPC host simply stops resolving.
`rpc.sapphire.testnets.gno.land` went on 2026-09-22, `rpc.pearl.testnets.gno.land` by
2026-09-29 (no DNS record, curl reports `000`). Each is removed from `defaultNetworks()`
rather than kept with a warning, because a name in that list is a publish target and
`NET=pearl` would have built a script against a dead endpoint and failed like a network blip.
**Check the testnet still resolves before planning a publish against it**: this is the third
one in five weeks.

onyx exposes `rpc.<net>.testnets.gno.land`, gnoweb at
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
chain the package paths point at, and sends the rest in dependency order with your terminal
attached. `PRINT=1` writes the commands out and runs nothing. gnopm holds no key and signs
nothing: gnokey does, and it prompts exactly as it would if you had typed the command.

**One signature per dependency LAYER, not per package** (gnopm v0.7.2). A layer is packages
that do not import each other, so the order they execute in cannot matter and one
transaction covers the layer. This workspace is 80 packages five layers deep: **6 prompts,
not 80**. `-one-tx-per-package` is the way back to a transaction each, for when a layer is
too big to review in one document or a failure should stop at exactly one package.

Layers rather than the whole graph in one transaction, deliberately: messages in a
transaction do share a store and run in order, but on a chain with an inert submission
policy `add_package` **parks** the bytes instead of making the package live, so a dependency
in the same transaction would not be there for the next message to import. Batching is also
capped at **70% of a block's gas**, which is `DefaultTargetGasRatio`: above it the chain's
dynamic gas price rises, and an uncapped batch is exactly the block that would raise the
price the rest of the same publish then pays.

Batching needs the signing address, because every message carries it as a field. gnopm asks
gnokey for its key list, or `-addr` names it; if neither answers it falls back to a
transaction per package and says so.

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

### On-chain status, and the two ways it asks

`make status` refreshes what is live where. It reads each chain with **two whole-chain
queries**, `vm/qpaths` and `vm/qinertpaths`, which between them name every package the chain
holds. They are disjoint and jointly complete, so a path in neither is absent, and a
288-contract catalog costs 2 queries per network instead of 288.

That matters because `rpc.gno.land` sits behind a load balancer that starts answering `403`
to every request, `/status` included, once queries arrive fast enough, and clears on its own
a few minutes later. A per-package sweep trips it: one on 2026-09-28 got 93 answers and then
195 refusals.

A chain that does not answer `vm/qpaths` falls back to a query per package, paced, stopping
after ten unanswered in a row rather than deepening a block. The run says which way it went.

The per-package query is **`vm/qpkgmeta_json`**, not `vm/qfile`. Under an inert
code-submission policy a successful `MsgAddPackage` parks the bytes and `vm/qfile` then
answers "not available", character for character what it answers for a path nobody ever
published, so a queued publish and a missing one were indistinguishable. `qpkgmeta_json`
answers `live` / `inert` / `absent`, and the catalog carries all three: a parked package is
`state: "inert"` with `uploaded: false`, and renders `⏳` in the README table.

Two older failures this still has to avoid, both of which cost a whole column once:

- **A chain that is down must not read as a chain that hosts nothing.** Each network is
  probed once with an HTTP `/status` call and skipped if it does not answer, and a skipped
  network keeps stale data rather than wrong data.
- **Anything unparseable is unknown, never absent.** An answer the tool cannot read leaves
  the recorded value alone. Inventing an absence is the one mistake that looks like a clean
  result.

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
in each: [`.github/ci-internals.md`](./.github/ci-internals.md).

## Conventions

- **Commits**: conventional, single line (`feat(hello): …`, `fix: …`,
  `chore(deps): vendor …`). Never a Claude or AI co-author trailer.
- **Author**: `Manfred Touron <94029+moul@users.noreply.github.com>`, the push-safe
  noreply identity.
- **Never hand-edit** the region between the README table markers, or the generated fields
  of `contracts.json` (`pkgpath`, `dir`, `kind`, `name`, `version`, `deps`).

## Meta issues: the hubs, and the shape they share

A `[meta]` issue is a **hub**: the one place for everything about one theme, so a narrow
thought becomes a comment there rather than a fourteenth issue nobody finds again. Eight
exist, they cross-link each other in an identical footer, and **GitHub pins at most three per
repository**, which is why the footer carries all of them.

| # | hub |
|---|---|
| [#97](https://github.com/moul/gno-contracts/issues/97) | port ideas: the backlog of structures, patterns and algorithms |
| [#172](https://github.com/moul/gno-contracts/issues/172) | gnopm |
| [#176](https://github.com/moul/gno-contracts/issues/176) | the `x/` experiments namespace |
| [#177](https://github.com/moul/gno-contracts/issues/177) | on chain: publishing, and what is live |
| [#178](https://github.com/moul/gno-contracts/issues/178) | render: how a realm shows itself |
| [#179](https://github.com/moul/gno-contracts/issues/179) | cost: gas, storage deposit |
| [#180](https://github.com/moul/gno-contracts/issues/180) | upstream: the `gnolang/gno` relationship |
| [#241](https://github.com/moul/gno-contracts/issues/241) | upgradeability: changing a realm whose path is permanent |

Write a new one only when a theme has outgrown being a comment on an existing hub. The shape,
which every one of them follows:

```
[meta] <topic>, everything about <topic>

<lede>          The one place for everything about X. Comment here rather than
                opening a narrow issue, until a thread is big enough to deserve its own.
## The goal              one bold sentence, then why it matters
## Where it stands today measured numbers, dated, in a table
## Where the code is     a path -> what table, linked
## How it got here       optional: the merged PRs that built it
---
# Decisions     numbered, each leading with the constraint that forced it
---
# Roadmap       numbered sections of checkboxes, ordered by what unblocks what
---
# Inspiration   optional: prior art worth stealing, and what to steal from it
# Principles    numbered, bold lead
# Non-goals     bullets, the lines that are not up for discussion
<footer>        the identical index of all eight
```

Three rules that matter more than the layout:

1. **Every number is measured and dated.** "188 of the 339 live `gno.land/*` packages on
   mainnet are ours, 2026-09-20" is worth writing down. "most of them" is not, and a figure
   with no date rots without anyone noticing.
2. **Nothing is claimed that was not run.** A command, a query path, a field name: run it
   first, or leave it out.
3. **No em dashes**, in the body or in any comment on it.

Ticking a box means the pull request that closes it is **merged**, and the line gains its
number: `- [x] ... (#123)`.
