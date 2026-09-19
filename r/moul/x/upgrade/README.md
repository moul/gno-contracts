# Upgrade patterns

A gno.land package path is permanent. `AddPackage` refuses an occupied path, so
a realm other people import can never have its code replaced. Every way of
shipping a v2 is therefore a way of arranging *several* realms so that one of
them can change while the path callers hold does not.

This folder collects the arrangements, each as a working, tested realm set.

Patterns A to F were originally explored in `gnolang/gno` under
`examples/gno.land/r/x/manfred_upgrade_patterns` (2024, removed from the
monorepo since). They are re-imported here and **ported to gno 0.9**: crossing
functions, `chain`-era stdlibs, `p/nt/*`, and this repo's version-last path
convention. The port is where most of the new findings came from, because
several of the originals no longer mean what they meant.

## The six

| Dir | Was | Idea | Upgrade is | Data moves | One answer? |
|---|---|---|---|---|---|
| [`wrap`](./wrap) | `upgrade_a` | Later version reads the earlier one and adds its own | a deploy, nothing else | never | **no**, every version reports its own total |
| [`lock`](./lock) | `upgrade_b` | Predecessor is retired one-way; successor folds its frozen total in | a deploy + one `Retire` tx | never | yes, at most one version is writable |
| [`store`](./store) | `upgrade_c` | A data realm owns the state and authorizes exactly one logic realm | one `SetLive` tx | never (it never left) | yes |
| [`lazy`](./lazy) | `upgrade_d` | New layout, records converted on first touch | a deploy, nothing else | per record, on read | yes |
| [`selfreg`](./selfreg) | `upgrade_e` | Permanent facade holds an interface; impl registers itself from `init` | a deploy, nothing else | never | yes |
| [`adminreg`](./adminreg) | `upgrade_f` | Same, but nominating and accepting are separate transactions | a deploy + one `Accept` tx | never | yes |

Read them in that order. `wrap` is the cheapest and weakest; each of the next
buys one guarantee back and charges a transaction, a gate, or a realm for it.

Choosing, very roughly:

- **The old version can keep running forever and nobody needs a single total** → `wrap`.
- **You need a single total and you control the switch** → `lock`.
- **You expect to change the logic repeatedly and never the data** → `store`.
- **The stored shape itself changes** → `lazy` (it composes: the successor of a
  `store` or `lock` can migrate lazily).
- **Callers must not have to know a version exists** → `selfreg`.
- **Same, but deploying must not be enough to take the realm over** → `adminreg`.

## What the port changed

The originals were written before interrealm. Porting them surfaced five things
that are not cosmetic.

1. **Migrating on read is now a transaction.** `lazy`'s whole appeal was a plain
   getter that quietly converted a record. Writing means crossing, so `Get` has
   to be `Get(cur realm, key string)`: it costs gas, and it is invisible to
   `vm/qeval` and to `Render`. `lazy/v1` therefore ships `Peek`, a read-only
   half that converts on the fly without storing, and answers differently from
   `Get` for any record nobody has touched yet. The two-answer window is the
   price, and it did not exist in the 2024 version.

2. **The caller's path is read off the frame, not passed in.**
   `cur.Previous().PkgPath()` replaces the old `std.PreviousRealm()`, and every
   gate here uses it. A candidate realm cannot claim to be a path it does not
   occupy, which is what makes `store` and `selfreg` safe to gate by prefix at
   all. The originals' `std.AssertOriginCall()` + `std.CallerAt(2)` + hardcoded
   admin string idiom is gone entirely; `p/nt/ownable/v0` covers it.

3. **`nestedpkg` no longer fits.** The original pattern E gated registration
   with `nestedpkg.AssertCallerIsSubPath()`, which works when the impl lives
   *under* the facade (`upgrade_e` and `upgrade_e/v1impl`). With the version
   segment last (`selfreg/facade/v0`, `selfreg/impl/v0`), no sibling is a
   sub-path of another, and the other shipped helper, `IsSameNamespace`, would
   let any realm in the namespace seize the facade. Both patterns here use an
   explicit path prefix instead. Version-last paths and `nestedpkg` are simply
   not compatible.

4. **An implementation cannot travel in a transaction argument.** The original
   pattern F had an admin call `home.SetImpl(impl)`, handing the facade an
   interface value. A wallet cannot put one in a `maketx call`: only strings and
   numbers travel, so that shape is reachable only from `maketx run` or from
   another realm. `adminreg` splits it in two instead, which is what makes both
   halves ordinary transactions: the impl **proposes itself** from its own
   `init`, and the owner **accepts a path string**. This is the same two-phase
   shape gno.land itself uses when the chain parks a submission until an
   approver enables it.

5. **A realm that hands out one of its own objects can never be private.** The facade
   holds an interface value whose concrete type is declared in the implementation
   realm, and marking that realm `private = true` aborts on the first call:

   ```
   panic: cannot persist object from the private realm gno.land/r/moul/x/upgrade/selfreg/impl/v1
   ```

   Measured 2026-09-28, and it is broader than it looks: the object here is
   `greeter{}`, a struct with **no fields at all** and value receivers. Being
   declared in your realm is enough; it does not have to be a pointer and does
   not have to carry state. Every implementation realm in `selfreg` and
   `adminreg` therefore carries a `# public:` line quoting that panic, on a path
   where the flag can never be changed again.

## The seventh pattern is the chain's own

`private = true` in a realm's `gnomod.toml` buys exactly one thing: **its creator may
re-add the package at the same path** instead of abandoning it for a `/vN+1`. That is
an upgrade mechanism, and it is the only one here that gno itself provides.

It costs three things: nobody may import you, nobody may hold an object you own, and a
redeploy re-runs `init()`, so every package-level variable is back to its initializer.
Which is to say it suits a realm that holds **no state and no callers**, and that is
exactly what pattern C's logic realm is.

So `store/logic/gen1` ships `private = true`, and the three measurements behind that
(2026-09-28) are worth more than the flag:

| Realm | Flag | Result |
|---|---|---|
| hands its own object to another realm (`selfreg/impl/v1`) | `private = true` | aborts: `cannot persist object from the private realm` |
| passes only scalars, nobody imports it (`store/logic/v1`) | `private = true` | green, and redeployable in place |
| passes only scalars, one test imports it (`store/logic/v0`) | `private = true` | fails to build: `import path ... is private and cannot be imported` |

The middle row is the interesting one. A pattern C logic realm does not need `SetLive`
to fix a bug: it needs a redeploy at the same path, which the chain already allows. Use
`SetLive` for the change you want a new reviewable path for, and the redeploy for the
one you do not. What you give up is that nothing may ever import that logic realm, so
the gate has to live in the data realm, which in pattern C it already does.

## A note on the layout

The directories are `gen0` and `gen1`, not `v0` and `v1`. This repo's rule 1 is that the
version is the `module` line and never a directory name, because a `vN` directory is how
a bump becomes a copy that git cannot diff. The module lines here still read
`.../wrap/v0` and `.../wrap/v1` and that is what publishes; the directory names only have
to be distinct, because these are the one case the rule did not anticipate: two
**generations that are both live on purpose**, each importing the one before it, rather
than one superseding the other.

## What none of them fix

- **Every version you ship is permanent cost.** Superseded realms stay deployed
  with their storage deposits. `lazy` is the worst case: migration *copies*, so
  the old realm keeps paying for every record forever (`lazy/v0.Size()` never
  shrinks).
- **Rolling back restores code, not data.** `store` and `adminreg` roll back in
  one call, and neither undoes a single byte a bad version wrote.
- **An upgradeable realm cannot export trust.** Per gno's interrealm spec, two
  mutable realms cannot export trust to each other, because the functions in
  both can be replaced. Everything downstream of `selfreg` or `adminreg` is
  trusting the owner, not the code. Nothing here yet ends that; see below.

## Prior art, and where this goes next

**[`clockworkgr/gno-upgradeable`](https://github.com/clockworkgr/gno-upgradeable)**
is the most developed version of the facade idea (patterns E and F) and is worth
reading in full. It keeps a permanent realm that holds only a pointer, and adds
three things none of the six have:

- **The API is data.** One `Call(cur realm, verb, payload string) string` entry
  point plus a declared schema, so verbs can be added forever, callers can
  enumerate them (`Verbs`, `Signature`, `SchemaJSON`), and payloads are checked
  before the handler runs. `adminreg`'s Go interface is frozen at deploy the way
  every Go interface is; a schema is not.
- **The upgrade is diffed.** `accept` refuses a handler whose schema would drop
  or reshape a verb an existing caller depends on, unless you confirm it
  explicitly. `adminreg` accepts any candidate satisfying the interface, which
  catches signature breaks and nothing about behaviour.
- **Upgradeability can be ended.** `Freeze` makes the realm permanent, which is
  the only way out of the "cannot export trust" bind above.

It carries no LICENSE file, so nothing from it is vendored here.

Open threads, roughly in order of interest:

1. **A `freeze` terminal state** for `selfreg` and `adminreg`. Cheap to add, and
   it is the answer to the trust problem, not a mitigation of it.
2. **Schema dispatch as a seventh pattern**, built here rather than copied, to
   measure what the string boundary actually costs against `adminreg`'s typed
   one.
3. **Paged migration** next to `lazy`: an owner-driven `MigrateN(n)` that drains
   the predecessor in bounded batches, so the two-answer window closes instead
   of lasting forever.
4. **A paged `private` variant of pattern C**: if the logic realm is redeployable in
   place, how much of `SetLive` is left, and is the data realm's path gate still the
   right shape when the writer's path never changes?
5. **What GovDAO-owned upgradeability looks like**, replacing `ownable` with a
   proposal in `store`, `lock` and `adminreg`.
