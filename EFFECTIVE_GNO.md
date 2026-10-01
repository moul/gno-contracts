# Effective Gno: the recipe book

**You are writing a gno realm and a decision is in front of you. This file is the answer,
plus the library that already implements it.**

The official [Effective Gno](https://docs.gno.land/resources/effective-gno/) teaches the
language and its idioms: embrace globals, embrace `panic`, prefer `avl.Tree` over `map`,
design a realm as a public API. Read it first, it is the foundation and this file does not
repeat it. What it deliberately does not do is tell you *which package to import*, because
upstream cannot bless one author's library over another's.

This repository can. Everything below is a routing decision taken once, measured where a
measurement was possible, and pointed at an implementation in
[`p/moul/*`](./README.md#contracts) that CI builds and tests on every commit. Where the
right answer is "use the stdlib" or "use somebody else's package", it says that instead.

**Three things to know before you use it.**

1. **Every recipe links to a working example in this repo.** If a claim here and the code
   there disagree, the code is right and this file is a bug. Nothing here is aspirational:
   an API sketch that does not work yet is marked 🚧 and you should not import it.
2. **It is opinionated on purpose.** "Use a map" is not a neutral statement in an ecosystem
   whose canonical doc says use `avl.Tree`. Where this file departs from upstream advice it
   says so, and shows the number that changed its mind.
3. **`AGENTS.md` is a different document.** That one is how to *work in this repository*:
   the versioning rules, the CI guards, the toolchain traps. This one is how to *write a
   contract*, here or anywhere. An agent working on this repo reads both.

> Inspired by, and meant to be read after: [Effective
> Gno](https://docs.gno.land/resources/effective-gno/), [Effective
> Go](https://go.dev/doc/effective_go), and the two books that taught a generation to think
> in recipes, *Effective C++* and the *Python Cookbook*. Where those teach the language,
> this one picks the library.

---

## Table of contents

| | |
|---|---|
| [0. The router](#0-the-router) | one table, the whole document |
| [1. Shape](#1-shape-what-you-are-building) | `p/` or `r/`, versions, private, the library plus demo split |
| [2. Storage](#2-storage-you-are-charged-for-objects-not-for-data) | which structure, and what it costs |
| [3. Render](#3-render-the-only-public-surface-a-realm-has) | markdown, tables, links, pagination, escaping |
| [4. Money](#4-money) | coins, tokens, receiving, paying out, formatting, rounding |
| [5. Authority](#5-authority-who-is-allowed-to-do-this) | the caller, ownership, DAOs, modules, the anti-patterns |
| [6. Time, height and randomness](#6-time-height-and-randomness) | the three things a realm cannot make up |
| [7. Errors](#7-errors-panics-and-aborts) | when to return, when to abort |
| [8. Testing](#8-testing) | what a realm test has to pin |
| [9. Cost](#9-cost-gas-storage-deposit-and-the-deploy) | before you deploy, and after |
| [10. Do not hand-roll this](#10-do-not-hand-roll-this) | the index of things already written |
| [Upstream reading](#upstream-reading) | what to read at docs.gno.land, and when |

---

## 0. The router

**The whole document, as one lookup.** Find your sentence, take the package, read the
section if you need the reasoning.

### Storing things

| I want to store | Use | § |
|---|---|---|
| one value, one struct, a counter | a package-level `var`. Nothing else | [2.2](#22-one-value-is-a-package-level-var) |
| a keyed map, no ordering needed | a native gno **`map`**. 153 B/entry, O(1), deterministic | [2.4](#24-keyed-and-unordered-is-a-map) |
| a keyed store you iterate in order, range or paginate | **`p/nt/bptree`**, at fanout 128 if entries are only added, 32 if they are removed | [2.5](#25-keyed-and-ordered-is-a-b-tree-at-high-fanout) |
| the same, but you inherited `avl` | keep reading, but new code should not start there | [2.5](#25-keyed-and-ordered-is-a-b-tree-at-high-fanout) |
| an append-only log under ~4,000 entries | a plain **`[]T`**. Nothing is cheaper | [2.6](#26-append-only-is-a-slice-until-about-4000-entries) |
| an append-only log above that, or one that deletes | [`p/moul/ulist`](./p/moul/ulist) | [2.6](#26-append-only-is-a-slice-until-about-4000-entries) |
| numbered records with an auto-incrementing id | [`p/moul/kit/store`](./p/moul/kit/store) | [2.7](#27-numbered-records-are-kitstore) |
| a set of addresses | [`p/moul/addrset`](./p/moul/addrset) | [2.8](#28-sets-queues-and-dedup) |
| a fixed-size recent-N buffer | [`p/moul/fifo`](./p/moul/fifo) or [`x/daily/ringbuffer`](./p/moul/x/daily/ringbuffer) | [2.8](#28-sets-queues-and-dedup) |
| a queue you only ever scan | a plain `[]T`, **not** `deque` | [2.8](#28-sets-queues-and-dedup) |
| a scoreboard, ranked | [`p/moul/kit/tally`](./p/moul/kit/tally) | [2.9](#29-scoreboards-are-kittally) |
| records with more than one lookup key | the store, plus one [`p/moul/kit/index`](./p/moul/kit/index) per key | [2.10](#210-more-than-one-index) |
| an expensive computation you repeat | [`p/moul/memo`](./p/moul/memo) | [2.11](#211-caching-and-snapshots) |
| a snapshot of a tree you can diff against | [`p/moul/cow`](./p/moul/cow) | [2.11](#211-caching-and-snapshots) |
| state you intend to delete and get the deposit back for | a map or a tree. **Never a slice** | [2.12](#212-deleting-and-the-refund) |

### Showing things

| I want to render | Use | § |
|---|---|---|
| a markdown table | [`ui.NewTable`](./p/moul/kit/ui). **Never string concatenation** | [3.2](#32-a-table-is-uinewtable-and-never-a-string-you-built) |
| headings, lists, links, code, collapsibles, columns | [`p/moul/md`](./p/moul/md) | [3.1](#31-markdown-is-pmoulmd) |
| anything a user typed | `ui.Inline` in prose, `ui.Cell` in a table. Always | [3.3](#33-anything-a-caller-typed-is-attacker-controlled-markdown) |
| a sub-page of my realm (`:posts/42`) | [`p/moul/realmpath`](./p/moul/realmpath) | [3.4](#34-routing-render-is-realmpath) |
| page 3 of a long list | [`p/moul/pageable`](./p/moul/pageable) | [3.5](#35-pagination-is-pageable) |
| a clickable "call this function" button | [`ui.Action`](./p/moul/kit/ui), or [`p/moul/txlink`](./p/moul/txlink) | [3.6](#36-a-button-is-uiaction) |
| an address, short and linked | `ui.Addr` | [3.7](#37-addresses-amounts-and-empty-states) |
| an amount of GNOT | `num.GNOTf` | [3.7](#37-addresses-amounts-and-empty-states) |
| a percentage from basis points | `num.Pct` | [3.7](#37-addresses-amounts-and-empty-states) |
| "nothing here yet" | `ui.Empty`, or `table.OrEmpty` | [3.7](#37-addresses-amounts-and-empty-states) |
| a chart, a gauge, an avatar | [`p/moul/svg`](./p/moul/svg) | [3.8](#38-pictures) |
| a tiny inline trend | [`x/daily/sparkline`](./p/moul/x/daily/sparkline) | [3.8](#38-pictures) |
| diagnostics for me but not for readers | [`p/moul/debug`](./p/moul/debug) | [3.9](#39-a-debug-panel-nobody-else-sees) |
| a link into a block explorer | [`p/moul/mygnoscan`](./p/moul/mygnoscan) | [3.8](#38-pictures) |
| a banner pointing at my web2 frontend | [`p/moul/web25`](./p/moul/web25) | [3.8](#38-pictures) |

### Moving value

| I want to | Use | § |
|---|---|---|
| read the coins attached to this call | [`p/moul/x/envelope`](./p/moul/x/envelope) | [4.2](#42-receiving-coins-is-envelope) |
| refuse a call that did not pay enough | `envelope.RequireAtLeast` | [4.2](#42-receiving-coins-is-envelope) |
| pay many people | credit a ledger, let them withdraw: [`x/daily/pullpayment`](./p/moul/x/daily/pullpayment) | [4.3](#43-paying-out-is-a-pull-never-a-push) |
| issue a token | `p/nt/grc20`, not a hand-rolled balance map | [4.1](#41-coins-or-a-grc20) |
| wrap a token I do not control | [`p/moul/x/grc20wrap`](./p/moul/x/grc20wrap) | [4.1](#41-coins-or-a-grc20) |
| split an amount N ways and have it add up | [`x/games/prorata`](./p/moul/x/games/prorata) | [4.5](#45-rounding-is-the-money-question) |
| multiply then divide without overflowing | `xmath.MulDiv` / `MulDivUp` | [4.5](#45-rounding-is-the-money-question) |
| know what this account can actually spend | [`p/moul/vesting`](./p/moul/vesting) | [4.6](#46-vesting-is-a-chain-rule-not-your-rule) |
| decide whether deleting state pays for itself | [`p/moul/x/storagecost`](./p/moul/x/storagecost) | [9.2](#92-storage-deposit-is-locked-not-spent) |

### Deciding who may act

| I want to | Use | § |
|---|---|---|
| know who called me | `cur.Previous()` under `cur.IsCurrent()`. **Never `OriginCaller`** | [5.1](#51-the-caller-is-curprevious-and-nothing-else) |
| have one owner | `p/nt/ownable` | [5.2](#52-one-owner-or-a-set-of-them) |
| have a set of members, transferable to a DAO later | [`p/moul/authz`](./p/moul/authz) | [5.2](#52-one-owner-or-a-set-of-them) |
| let only realms under my path call me | [`p/moul/nestedpkg`](./p/moul/nestedpkg) | [5.3](#53-authority-by-package-path) |
| stop the realm in an emergency | [`p/moul/pausable`](./p/moul/pausable) | [5.4](#54-a-pause-switch) |
| add powers to a live realm without redeploying it | [`p/moul/pilot`](./p/moul/pilot) | [5.6](#56-powers-installed-after-the-fact-pilot) |
| run a grant program | [`p/moul/grants`](./p/moul/grants) | [5.5](#55-collective-decisions) |

### The rest

| I want to | Use | § |
|---|---|---|
| a random-looking number | [`p/moul/entropy`](./p/moul/entropy), and never for money | [6.3](#63-randomness-does-not-exist-here) |
| a deadline that actions push forward | [`x/games/clock`](./p/moul/x/games/clock) | [6.1](#61-height-is-the-clock-you-can-trust) |
| a rate limit | [`x/daily/ratelimit`](./p/moul/x/daily/ratelimit) | [6.1](#61-height-is-the-clock-you-can-trust) |
| a commit-then-reveal round | [`x/daily/commitreveal`](./p/moul/x/daily/commitreveal) | [6.3](#63-randomness-does-not-exist-here) |
| to combine several errors | [`p/moul/errs`](./p/moul/errs) | [7](#7-errors-panics-and-aborts) |
| `min`, `max`, `clamp`, `abs` on a numeric type | [`p/moul/xmath`](./p/moul/xmath) | [10](#10-do-not-hand-roll-this) |
| to format bytes, ordinals, plurals | [`x/daily/humanize`](./p/moul/x/daily/humanize) | [10](#10-do-not-hand-roll-this) |
| a Merkle proof | [`p/moul/x/merkle`](./p/moul/x/merkle) over the native `crypto/merkle` | [10](#10-do-not-hand-roll-this) |

---

## 1. Shape: what you are building

### 1.1 `p/` or `r/`

A **`p/` package** is pure, versioned, importable and forever. It holds no realm state, it
cannot declare a crossing function (`func F(cur realm, …)` in a non-realm package fails to
build), and once published at `gno.land/p/<ns>/<name>/vN` that path is immutable.

An **`r/` realm** has state, an address, and a `Render`. It is the only place a crossing
function can live.

**The default split for anything reusable is a pure library plus a thin demo realm.** The
library holds the algorithm and takes the height, the caller and the amount as arguments;
the realm wires it to the chain and shows it through `Render`, with no logic of its own.
Worked pairs: [`p/moul/x/daily/ratelimit`](./p/moul/x/daily/ratelimit) plus
`r/moul/x/daily/ratelimitdemo`, [`p/moul/forge`](./p/moul/forge) plus
[`r/moul/forge`](./r/moul/forge).

Keep a lone realm only when the thing is inherently a stateful app with nothing reusable
inside it.

**Why it matters more here than in Go.** A package path on this chain cannot be reused: a
public `AddPackage` at an occupied path is refused. Logic trapped inside a realm you later
want to fix is a new path and a migration. Logic in a `p/` is a `vN+1` that the old callers
keep resolving.

### 1.2 The version is real, and it is in `gnomod.toml`

New contracts start at `v0`, which is gno's own convention for *initial and unaudited*
([gnolang/gno#5220](https://github.com/gnolang/gno/issues/5220)). The version lives in the
`module` line, never in a directory name, so a breaking change is a one-line edit plus the
real content diff instead of a copied directory git cannot pair.

Breaking, and therefore a `vN+1`: removing or renaming an exported symbol, changing a
signature, changing on-chain behaviour, swapping the backing storage. Everything else,
including new exported functions, edits the current version in place.

Mechanics, and the tool that does it: [AGENTS.md § Bumping a
contract](./AGENTS.md#bumping-a-contract).

### 1.3 `private = true` is the default for a realm

A realm whose `gnomod.toml` declares `private = true` can be **redeployed at the same path
by its original creator**. Everything else about a deployed path is a one-way door, so this
is decided once, before the first publish, and after that neither direction converts.

Measured on `gnolang/gno@master` with the integration harness, 2026-09-22:

| across a redeploy | |
|---|---|
| the code | replaced |
| coins at the realm address | **kept** |
| every package-level variable | **wiped**, back to its initializer |
| storage deposit | accumulates; prior objects are never evicted and nothing can free them |

The price is that **no other realm may import it**, hold a reference to its objects, or
retain a value of a type it defines. The import is a type-check error; the other two are a
runtime panic that `gno lint` cannot see.

So: **private by default, and a realm that must stay importable says why in a comment.**
The default is not a claim that replacing beats versioning. It is a claim about which
mistake is cheaper to undo.

The thing that makes private genuinely safe is designing for the wipe: keep the durable
part where a redeploy does not reach (coins at the address, or a local source of truth you
can push back), or accept losing it.

### 1.4 One realm per instance, not one realm with a registry

Gno has no generics and no cheap way to hand a caller a live typed handle across realms.
The pattern that falls out of that is **instance per realm**: the shared behaviour is a
`p/` package, and each instance is a twenty-line realm that holds one value of the
package's type and forwards its own `cur`.

[`p/moul/x/pair`](./p/moul/x/pair) is the worked example: one constant-product AMM pair as
a pure package, so the realm holding a pair is glue.
[`p/moul/x/framelab`](./p/moul/x/framelab) is the thirty-line probe that pins the language
property it rests on, that pure-package code runs in the frame of the realm that imported
it when that realm forwards its own `cur`.

### 1.5 Declare your types and interfaces in `p/`

Upstream says this and it is worth repeating with the local consequence: a type declared in
a realm is unusable by anyone else, and a **private** realm's type is unusable by anyone
else *and* poisons any object that retains it. Interfaces, value types and errors go in a
`p/`. [`p/moul/udao`](./p/moul/udao) is the shape: the DAO interface written from the
outside, deliberately exposing only what a non-member can act on.

---

## 2. Storage: you are charged for objects, not for data

### 2.1 The cost model, in four numbers

Everything in this section follows from one table. Measured 2026-09-29 against
`gnolang/gno` master `1fc4c140e`, from `Store.RealmStorageDiffs()`, which is the same
number the chain charges the storage deposit on.

| what | cost |
|---|--:|
| a byte of string content | **1 B, exactly** |
| an extra struct field | ~73 B |
| a declared struct value, even stored inline | **~347 B** |
| a pointer, that is, a separately persisted object | **~372 B** |
| a slice slot holding a scalar | ~63 B |

**You are not charged for data. You are charged for objects.** Every structural decision in
gno is a decision about how many objects you create, and a 400-byte structural tax dwarfs
anything you will do to your keys.

Two corollaries that save real money:

- **`any` is free.** `[]string` and `[]any` holding the same strings are identical byte for
  byte, and so are `map[string]string` and `map[string]any`. Interface boxing costs about
  0.4% in gas and nothing in storage. Type your containers for readability.
- **Storing a live object instead of an encoded string costs a flat +780 B per entry**, in
  every container, independent of the container. It is the pointer plus the struct plus a
  field. If an entry is read whole and never mutated field by field, encode it.

### 2.2 One value is a package-level `var`

Upstream's "embrace global variables in realms" is correct and there is nothing to add: a
realm's package-level variables *are* its database, and `init()` runs exactly once, at
deploy. No container, no wrapper, no accessor generated for its own sake.

The only thing to design is the **wipe**: under `private = true` every package-level
variable goes back to its initializer on redeploy (§1.3).

### 2.3 The decision table

n = 1,000, string values, measured as above. Gas figures are filetest gas, comparable to
each other and not a fee estimate; the byte counts are real.

| If you need | Use | Why |
|---|---|---|
| a keyed store, no ordering | **`map[string]T`** | 153 B/entry, 4.2k gas/read, 57k gas/write, all O(1) |
| ordered iteration, range, pagination | **`p/nt/bptree` at fanout 128**, or 32 if entries are removed ([2.5](#25-keyed-and-ordered-is-a-b-tree-at-high-fanout)) | 592 B/entry, 64k gas/read, 8k gas per entry iterated |
| a positional append-only log under ~4k entries | **a plain `[]T`** | 79 B/entry, 3.1k gas/read, nothing cheaper exists |
| a log above ~4k entries, or one that deletes | [**`p/moul/ulist`**](./p/moul/ulist) | 923 B/entry buys stable indices, a flat append, a partial refund |
| a queue you only ever scan | **a plain `[]T`**, not `deque` | `deque` is 1,043 B/entry and 534k gas for a random read |
| anything at all | **not `avl`** | 2,029 B/entry and dominated on every workload measured |

Bytes per entry, same n, so you can see the spread rather than take it on faith:

| structure | B/entry | vs the map |
|---|--:|--:|
| `map[string]any` | 153 | 1.0x |
| `[]T` (positional) | 79 | n/a, no keys |
| sorted `[]struct{K,V}` | 496 | 3.2x |
| `bptree` fanout 128 | 592 | 3.9x |
| `bptree` fanout 32 (the package default) | 671 | 4.4x |
| [`p/moul/ulist`](./p/moul/ulist) | 923 | n/a, positional |
| [`p/moul/deque`](./p/moul/deque) | 1,043 | n/a, positional |
| `avl` | 2,029 | 13.3x |
| [`p/moul/cow`](./p/moul/cow) | 2,041 | 13.3x |

Deposit is bytes times 100 ugnot, the chain's default `storage_price`. 100,000 entries in
an `avl` locks 20,290 GNOT. In a map, 1,530.

### 2.4 Keyed and unordered is a `map`

**This is where this document departs from upstream, which says prefer `avl.Tree` over
`map` for scalable storage.** That advice is right about Go's map, whose iteration order is
randomised and therefore a consensus bug. Gno's map is not Go's map.

Verified 2026-09-29 against the installed toolchain, inserting `k0 k7 k6 k5 k4 k3 k2 k1`,
then deleting `k6` and re-adding it:

```
k0 0
k7 1
k5 3
k4 4
k3 5
k2 6
k1 7
k6 99
```

**Gno map iteration is deterministic and in insertion order**, and a delete-then-re-add
moves the key to the end. A map is chain-safe. It is also one persisted object, which is
why it costs 153 B/entry against AVL's 2,029 and reads 19x cheaper.

What you give up is real and you should check it against your realm before reaching for
one:

- **no key order**, so no sorted page
- **no range scan**
- **no `GetByIndex`**
- **pagination is O(n) per page.** A map has no ordered access, so page 50 means fifty full
  scans. Measured: 22k gas per page at n=100, 213k at n=1,000, 2.1M at n=10,000. This is
  the one trap in an otherwise flat structure.

So: a map for lookup, a tree for anything a reader navigates.

### 2.5 Keyed and ordered is a B+ tree at high fanout

[`p/nt/bptree`](https://gno.land/p/nt/bptree/v0) beats `p/nt/avl` on every axis measured but
one (removal, below): 592 B/entry against 2,029, 153k gas per insert against 418k, 8k gas per entry iterated
against 47k. `avl` is leaf-oriented, so n entries make 2n-1 node objects, each holding two
child pointers; the keys were never the cost.

**Fanout is the cheapest lever you have.** Going from 4 to 128 is 2.5x on storage and 1.7x
on insert gas, for one integer at construction. The package's default of 32 is not the
cheapest point; 128 won every workload measured. The floor underneath that is the B+
tree's per-entry value box (`values []*any`, one separate object per entry for lazy
loading), which fanout cannot touch.

**Except on removal, where high fanout costs you.** Removing a key shifts every later value
in its leaf down one slot, and since each value is its own boxed object, every shifted one is
rewritten. That is about **90k gas per later entry in the leaf for a scalar value, and about
230k for a pointer** (a `*struct`, which is what a record store holds), so the cost of a removal
depends on where the key sits, and a full fanout-128 leaf makes its first key the most
expensive thing in the tree to delete. Measured 2026-10-02 on a real node (integration
txtar, one transaction per step, so store reads and writes are priced), `gnolang/gno` master
`3cc494ec4`, 120 string keys inserted in order, `int` values:

| tree | insert all 120 | remove the last key | the middle | the first |
|---|--:|--:|--:|--:|
| `bptree` fanout 128 (one leaf) | 19.2M | 5.1M | 10.4M | **15.8M** |
| `bptree` fanout 32 (four leaves) | 21.4M | 4.8M | 5.0M | 7.5M |
| `avl` | 55.8M | 6.6M | 6.6M | 6.5M |

With `*struct` values in the same fanout-128 leaf, the last key costs 5.2M and the first
**32.3M**.

So fanout 128 is right for a tree that only grows, a log or an index of things never
deleted. A tree whose keys are removed at arbitrary positions (a queue with expiry, a
registry with withdrawals, an index whose entries move) should use 32: 11% more on insert,
and the worst removal 2.1x cheaper. At 128 the worst removal costs 2.4x what `avl` charges,
the one workload where `avl` wins.

`avl` remains the ecosystem default and most example code you will read uses it. Two of its
API shapes have cost this repo a red CI more than once and are worth memorising, because
they are opposites on neighbouring methods of the same tree:

```gno
v := t.Get(k)                 // ONE value. A miss is a nil interface.
if v == nil { … }
p, ok := t.Get(k).(*poll)     // the comma-ok belongs on the type assertion

if _, removed := t.Remove(k); !removed { … }   // Remove returns TWO
```

### 2.6 Append-only is a slice, until about 4,000 entries

A plain `[]T` is the floor for an append-only log: 79 B/entry and 3.1k gas to read by
index. Nothing in gno is cheaper.

It has one growth surprise. **A slice's append gets more expensive as the slice grows**,
because the backing array is a single persisted object rewritten when it grows: 47k gas at
n=100, 82k at n=1,000, **292k at n=10,000**. [`p/moul/ulist`](./p/moul/ulist), which is a
tree, goes the other way: 84k then 112k then 126k. **They cross at roughly n = 4,000.**

Below that crossover a slice wins and you should not import anything. Above it, or the
moment you need to delete, `ulist` earns its 923 B/entry: stable indices (deletes are soft,
so an index another realm is holding never points at the wrong element), a flat append, and
a compaction story.

`ulist.Compact()` is asymmetric and the asymmetry is measured, n = 1,000, per element
deleted:

| what was deleted | `Compact()` frees | gas per element |
|---|--:|--:|
| the oldest half | **0 B** | 17,247 |
| a random half | 505 B | 17,415 |
| the newest half | 859 B | 17,427 |

Index 0 is the root and every newer entry keeps its ancestors alive, so compacting after
deleting the oldest entries pays 17k gas per element to free nothing. **Call
`Compactable()` first. It reads this for free.**

### 2.7 Numbered records are `kit/store`

Every realm here was writing the same three things by hand: an `avl.Tree`, an int counter,
and a private function that zero-pads the counter into a key so the tree iterates in the
order a human expects. [`p/moul/kit/store`](./p/moul/kit/store) is that, once.

```gno
import "gno.land/p/moul/kit/store/v0"

var games = store.Named("game")            // or: var games store.Store

func NewGame(cur realm) int64 {
	return int64(games.Add(&Game{Board: empty, X: caller()}))
}

func Move(cur realm, gameID int64, cell int) {
	g := games.MustGet(store.ID(gameID)).(*Game) // panics "game #7 not found"
	…
}

func Render(path string) string {
	for _, e := range games.PageReverse(1, 20) { // newest first, one page
		g := e.Value.(*Game)
		_ = e.ID
	}
}
```

The zero value is usable, `Named` only improves the panic message, and `Page` /
`PageReverse` / `Pages` mean you do not also import a pager for the common case.

**Do not pad ids by hand with `ufmt`.** `ufmt` supports no width flags at all:
`ufmt.Sprintf("%03d", 7)` returns `"7"`, silently, and unpadded numeric keys sort
`"0","1","10","11","2"`, so your list loses insertion order at the tenth entry. Use
`store`, whose key is a `seqid` binary encoding with no width to overflow, or
[`num.Pad`](./p/moul/kit/num) when you only need it for display.

### 2.8 Sets, queues and dedup

| you want | use |
|---|---|
| a set of addresses | [`p/moul/addrset`](./p/moul/addrset), B+ tree backed, zero value usable |
| the last N of something, dropping the oldest | [`p/moul/fifo`](./p/moul/fifo) or [`x/daily/ringbuffer`](./p/moul/x/daily/ringbuffer) |
| a bag with counts | [`x/daily/multiset`](./p/moul/x/daily/multiset) |
| a dense set of small integers | [`x/daily/bitset`](./p/moul/x/daily/bitset) |
| approximate counts in fixed space | [`x/daily/countminsketch`](./p/moul/x/daily/countminsketch) |
| a map you can look up in both directions | [`x/daily/bidimap`](./p/moul/x/daily/bidimap) |
| prefix search or autocomplete | [`x/daily/trie`](./p/moul/x/daily/trie) |
| a double-ended queue | **usually a plain `[]T`** |

The last row is the one to read twice. [`p/moul/deque`](./p/moul/deque) is the cheapest
thing measured to append to (68k gas) and the most expensive thing measured to index into
(534k gas at n=1,000, because `Get(i)` walks the list from the head), a 172x spread. A
deque you only ever scan is fine. **A deque that anything renders by index is a quadratic
bug waiting for traffic.**

Bounded is a feature, not a limitation. On chain an unbounded buffer is an unbounded
deposit that someone else is paying for.

### 2.9 Scoreboards are `kit/tally`

Ordering a scoreboard is the one place gno's missing `sort.Slice` bites every realm.
There is no `sort.Slice` in gno's `sort`: it has `Sort(Interface)` and the `Search*`
helpers, so every leaderboard was declaring its own `Len`/`Swap`/`Less`.

[`p/moul/kit/tally`](./p/moul/kit/tally) is that once, with the tie-break already decided:
highest score first, ties broken by key, which makes the order a total order and therefore
a `Render` that does not reshuffle between two identical calls.

```gno
b := tally.NewBoard()
b.Add("alice", 3)
for i, e := range b.Top(10) { … }
rank := b.Rank("alice")      // never ties
```

If you do write your own comparator: **break ties deterministically**, on the address or
the key, always. A `Render` whose output varies between identical calls is a consensus bug,
and gno map iteration order, while deterministic, is *insertion* order and not a sort.

### 2.10 More than one index

[`p/moul/collection`](./p/moul/collection) is the only multi-index store here and today it
is not the right answer: 2,080 B/entry with one extra unique index, and an **update costs
1.9x what creating the record cost** (964,833 gas against 508,977 at n=1,000) because
`Update` removes and re-adds every index entry for every index without first checking
whether the indexed value changed.

A record store with two lookup keys is two containers and a small amount of discipline: the
records in a [`kit/store`](./p/moul/kit/store), `key -> id` in a
[`kit/index`](./p/moul/kit/index), **both written in the same function**. A third of the
cost, and the realm can see what it is paying for.

```gno
var notes = store.Named("note")
var byTag index.Index // the zero value is an empty, usable index

func Post(cur realm, tag, body string) int64 {
	id := notes.Add(&note{Tag: tag, Body: body})
	if err := byTag.Add(tag, id); err != nil {
		panic(err) // the store write is not committed either: same frame
	}
	return int64(id)
}
```

The discipline is the one line that matters: **every write touches the store and every index
in one function**, so an abort anywhere leaves none of them applied. That is the whole
correctness argument for keeping them apart, and it is why the library deliberately does not
try to own the store. Worked example: [`r/moul/x/kitindexdemo`](./r/moul/x/kitindexdemo).

`kit/index` is a B+ tree at fanout 128, keeps the ids under a key ascending so a `Lookup`
does not depend on insertion order, and hands out a copy rather than its stored slice.

### 2.11 Caching and snapshots

[`p/moul/memo`](./p/moul/memo) caches a function result under a key, B+ tree backed:

```gno
m := memo.New()
result := m.Memoize("key", func() any { return expensive() })
m.Invalidate("key")
```

[`p/moul/cow`](./p/moul/cow) is an AVL fork with the same API plus **O(1) `Clone`**: the
snapshot shares every node, and only the root-to-leaf path is copied on the next write. It
is the right tool for "show me a diff against how this looked at block N", and the wrong
tool for everything else, because it pays 2,041 B/entry and 1.9x AVL on churn. Take the
snapshot, or take the cheap container. Not both by default.

### 2.12 Deleting, and the refund

The storage deposit is refunded on the **net byte delta**, to whoever signs the transaction
that frees the bytes. Trees and maps return essentially 100%. Slices return nothing, and
the obvious fixes do not work either. Measured, 500 entries of `struct{K, V string}`:

| what the realm does after building | bytes held | gas |
|---|--:|--:|
| nothing | 245,909 | 35.7M |
| `t = append(t[:0], t[1:]…)` until empty | **246,125** | 58.2M |
| `t[i] = kv{}` for every i | 211,129 | 36.4M |
| **`t = nil`** | **10** | 35.0M |
| the same with a map, `delete(t, k)` for every k | **15** | 15.0M |

Removing every element one by one **costs 22.5M extra gas and refunds nothing**: it ends
216 bytes heavier than never deleting anything. Zeroing each element gives back 14%, which
is the string content and only the string content, because the ~347-byte structural tax
belongs to the slot and the slot still exists.

> **A slice gives the deposit back when you drop the whole slice, and at no other time.** A
> realm that needs per-element deletion and its deposit back needs a map or a tree.

Whether it is worth paying gas to free bytes at all is arithmetic, and
[`p/moul/x/storagecost`](./p/moul/x/storagecost) is the calculator: `Evaluate` returns a
`Quote` whose `Worth()` answers it.

---

## 3. Render: the only public surface a realm has

`Render(path string) string` is what gnoweb calls, what an explorer indexes, and what a
human sees. It is also the function most likely to be wrong in a way nothing catches: it
takes no authority, returns a string, and a subtly non-deterministic one is a consensus
bug.

**Three rules, before any library.**

1. **Deterministic.** Never a wall clock, never a random value, never map iteration order
   used as a sort, never an unbroken tie.
2. **Escaped.** Everything a caller typed is attacker-controlled markdown (§3.3).
3. **Tested.** Every realm here pins its `Render` with an example test, and CI fails a realm
   that does not ([§8](#8-testing)).

### 3.1 Markdown is `p/moul/md`

[`p/moul/md`](./p/moul/md) is the builder set: `H1`..`H6`, `Bold`, `Italic`,
`Strikethrough`, `BulletList`, `OrderedList`, `TodoList`, `Nested`, `Blockquote`,
`InlineCode`, `CodeBlock`, `LanguageCodeBlock`, `HorizontalRule`, `Link`, `UserLink`,
`Image`, `InlineImageWithLink`, `Paragraph`, `CollapsibleSection`, `Columns`, `ColumnsN`,
`FootnoteDefinition`, `LinkReferenceDefinition`.

```gno
out := md.H1("Posts")
out += md.BulletList([]string{"first", "second"})
out += md.Link("gno.land", "https://gno.land")
out += md.CollapsibleSection("Details", md.CodeBlock(dump))
```

The one thing to learn about it is **which builders escape and which do not**, because
double-escaping is as wrong as not escaping:

```gno
out += md.Link(post.Title, post.URL)                                   // good: Link sanitizes
out += md.H2(sanitize.InlineText(post.Title))                          // good: H2 does not
out += md.H2(post.Title)                                               // BAD: raw user input
out += md.Link(sanitize.InlineText(post.Title), sanitize.URL(post.URL)) // BAD: double-wrap
out += md.H2(md.Link(post.Title, post.URL))                            // good: nest outward
out += md.Link(md.Bold(post.Title), post.URL)                          // BAD: Link escapes the ** back out
```

### 3.2 A table is `ui.NewTable`, and never a string you built

This is the single most repeated mistake in this repository's own history, which is why it
leads the section.

```gno
// BAD, and it is everywhere
sb.WriteString("| path | state | left |\n")
sb.WriteString("|---|---|---|\n")
sb.WriteString(ufmt.Sprintf("| `%s` | %s | %d |\n", m.path, m.state, m.left))
```

```gno
// GOOD
t := ui.NewTable("path", "state", "left")
t.Row(md.InlineCode(m.path), m.state, strconv.Itoa(m.left))
return t.OrEmpty("No modules installed.")
```

Four things the hand-rolled version gets wrong and the helper does not: a cell containing
`|` silently opens a new column; a short row silently drops data instead of padding; an
empty table renders as a header with no body instead of a sentence; and the separator row
has to match the header count, which nothing checks.

This repository enforces it: `make guard-tables` fails a package that builds a table
separator row by hand, against a baseline of the 100 that predate the guard. The opt-out is
`// handrolled-table: <what the dashes really are>`, which exists because a cow's horn in
ASCII art is `||----w |`.

**And the baseline is permanent, which is the real lesson.** 329 of the 331 contracts here are
live on mainnet, and a public package path is immutable: `AddPackage` refuses a path already
occupied unless the live package is private. So a realm that shipped a hand-rolled table
renders it forever, and the fix is a `vN+1` at a new path that every importer has to move to.
`p/moul/pilot` is the worked example and the reason this section exists: its account page was
rewritten through `ui.NewTable`, green, tests re-pinned, before anyone asked the chain, and
`p/moul/pilot/v0` turned out to have been live with 12,728 bytes of state the whole time. The
rewrite was reverted. **Get the table right before the first deploy, because there is no
second one.**

**Which table package.** Use [`ui.NewTable`](./p/moul/kit/ui) in anything that renders
caller-supplied text, which is almost everything. [`p/moul/mdtable`](./p/moul/mdtable) is
the older, simpler builder and is frozen as a byte-for-byte mirror of the copy in
`gnolang/gno`; it unconditionally rewrites `|` to `&#124;` in every cell, which
double-escapes when stacked on `ui.Cell` (whose GFM escape is `\|`) and leaves a stray
backslash. **One escaping stage, and it has to be the one that knows whether the text is
user input.** That is `ui`.

### 3.3 Anything a caller typed is attacker-controlled markdown

A title, a note, a nickname, a memo. It can be a link, an image, a table that breaks its
own column, or a bidi run that reverses the sentence around it. Wrap it once, at the call
site that builds the markdown:

| helper | for |
|---|---|
| `ui.Inline(s)` | a sentence, a list item, a link title |
| `ui.Cell(s)` | a table cell, which must not open a new column |
| `ui.Excerpt(s, n)` | the same, truncated, without ever stranding a backslash |

This repository enforces it with a CI guard rather than a review, and the reason is §1.1: a
public package path is immutable, so a realm that ships an unescaped `Render` keeps it
forever and the only fix is a new path. It was a convention until 2026-09-22 and the
convention lost, one pull request after twenty-five realms had been ported.

If every stored string is validated at write time instead (one letter, an enum, a semver, a
charset-checked word), say so in the file and mean it:

```gno
// untrusted-render: every stored word is checked against the a-z charset at write time
```

### 3.4 Routing `Render` is `realmpath`

The `path` argument carries both a path and a query string, and parsing it by hand is how
you get a realm that answers the wrong page for `?page=2&size=`.

```gno
func Render(path string) string {          // path = "posts/42?tab=raw"
	req := realmpath.Parse(path)

	switch req.PathPart(0) {
	case "":      return renderIndex(req)
	case "posts": return renderPost(req.PathPart(1))
	default:      return "404"
	}
}
```

`req.Query.Get("tab")` reads a parameter, and `req.String()` rebuilds the URL, which is
what you want when a page has to link to itself with one thing changed.
[`p/moul/realmpath`](./p/moul/realmpath) is shaped like `net/url` on purpose.

### 3.5 Pagination is `pageable`

Implement two methods and you get pages, page sizes, reverse order, the `?page=` and
`?size=` parsing, and the Markdown page picker:

```gno
pager := pageable.NewPager(source, 10 /* default size */, false /* reversed */)
page := pager.MustGetPageByPath(path)
for _, item := range page.Items { … }
out += page.Picker()
```

[`p/moul/kit/store`](./p/moul/kit/store) already has `Page`, `PageReverse` and `Pages`, so
a store-backed realm usually does not need the pager at all. Reach for
[`p/moul/pageable`](./p/moul/pageable) when the source is something else.

**Do not paginate a map.** §2.4: it is O(n) per page and 2.1M gas at n=10,000.

### 3.6 A button is `ui.Action`

A realm page can offer a transaction instead of telling the reader what to type.

```gno
ui.Action("Vote yes", "Vote", "id", strconv.Itoa(id), "choice", "yes")
```

Under it, [`p/moul/txlink`](./p/moul/txlink) builds the URL, with a builder for the cases
that need a send amount:

```gno
txlink.Call("AddTodo", "todo", "buy milk")
// -> /r/moul/home$help&func=AddTodo&todo=buy+milk

txlink.NewLink("Donate").AddArgs("message", "thanks").SetSend("1000000ugnot").URL()
```

[`p/moul/helplink`](./p/moul/helplink) is the same idea aimed at the gnoweb help page, and
`ui.ActionIn(pkgPath, …)` is the cross-realm form.

### 3.7 Addresses, amounts and empty states

| you are rendering | use | gives |
|---|---|---|
| an address | `ui.Addr(a)` | shortened and linked to its account page |
| the same, unshortened | `ui.AddrFull(a)` | |
| an address as text only | `ui.AddrText(a)` | |
| an amount in ugnot | `num.GNOTf(v)` | `"1.234567 GNOT"` |
| the same in a column | `num.DecFixed(v, 6)` | constant width, no trimmed zeros |
| a fee or a share in basis points | `num.Pct(bps)` | `Pct(1234)` is `"12.34%"` |
| a zero-padded number, for display | `num.Pad(v, 3)` | `"007"`, which `ufmt` cannot do |
| a rank | `ui.Podium(i)` | the medal for the first three, nothing after |
| nothing at all | `ui.Empty(msg)`, `t.OrEmpty(msg)` | a sentence instead of a blank page |
| optional sections | `ui.Join("\n\n", parts…)` | skips the empty ones, no stray separators |

### 3.8 Pictures

[`p/moul/svg`](./p/moul/svg) builds an SVG from a realm: `NewCanvas`, then `NewCircle`,
`NewRectangle`, `NewPath`, `NewPolygon`, `NewText`, `Group`. `Canvas.Render(alt)` emits a
markdown image with the SVG inlined as a data URI, so it needs no host and no round trip.

For something smaller: [`x/daily/sparkline`](./p/moul/x/daily/sparkline) turns a numeric
series into one line of block characters, and [`x/daily/cowsay`](./p/moul/x/daily/cowsay)
and [`x/daily/hexdump`](./p/moul/x/daily/hexdump) exist because ASCII is still the cheapest
picture there is.

Two link builders that save a hardcoded hostname: [`p/moul/mygnoscan`](./p/moul/mygnoscan)
builds explorer links from inside a realm, picking the network from the chain id, and
[`p/moul/web25`](./p/moul/web25) renders the one consistent line pointing at the web2
frontend that also serves this realm.

### 3.9 A debug panel nobody else sees

[`p/moul/debug`](./p/moul/debug) collects log lines while `Render` runs and appends them as
a collapsible section, but only when the reader asks with `?debug=1`:

```gno
func Render(path string) string {
	var d debug.Debug
	d.Log("loaded " + strconv.Itoa(n) + " items")

	out := renderPage()
	return out + d.Render(path)      // empty unless ?debug=1
}
```

`debug.ToggleURL(path)` gives you the link to put in the footer. This is how you avoid the
other thing: [`p/moul/printfdebugging`](./p/moul/printfdebugging), which prints in a colour
you cannot miss in a wall of test output and is, per its own first line, "a joke... or not".

---

## 4. Money

### 4.1 Coins or a GRC20

**Coins** are the chain's native ledger. They are real bearer value, they move with the
banker, and a realm holds them at its own address. Use them when the thing *is* money.

**A GRC20** is a realm-level ledger implemented by `p/nt/grc20`. Use it when you are
issuing something: shares, points, a wrapped asset. Do not hand-roll a `map[address]int64`
and call it a token; you will get the allowance semantics wrong and nothing will index it.

Wrapping a token you do not control is [`p/moul/x/grc20wrap`](./p/moul/x/grc20wrap):
`Vault` escrows an existing token and issues its own against it, `Basket` does it over
several, and a `Policy` decides the rate in both directions.

Upstream's [Choosing between Coins and GRC20
tokens](https://docs.gno.land/resources/effective-gno/#choosing-between-coins-and-grc20-tokens)
is the long form and is worth the read.

### 4.2 Receiving coins is `envelope`

The `-send` field of a call is credited to the realm's address before a line of its code
runs. Reading it correctly, and refusing the call when it is wrong, is
[`p/moul/x/envelope`](./p/moul/x/envelope):

```gno
amount := envelope.RequireAtLeast("ugnot", price)   // aborts, naming the flag to fix
```

`Amount`, `All`, `IsEmpty` read it; `Require`, `RequireAtLeast`, `RequireExactly`, `Only`
enforce it; `Forward` and `ForwardAll` pass it on.

**The trap that is not obvious.** `BankerTypeOriginSend` is gated on *who entered the
realm*, not on how deep you are: `NewBanker` requires `rlm.Previous().IsUserCall()`, and
`Realm.IsUserCall` is literally `r.pkgPath == ""`. So passing `cur` down through your own
helpers is fine, measured at three nested calls, through a function value and through a
closure. But **a realm called by another realm cannot forward the envelope, and
`maketx run` cannot reach a payable function at all.** Design the paid entry point to be
called directly by a user, or do not make it payable.

### 4.3 Paying out is a pull, never a push

A realm that loops over recipients and sends to each one fails entirely when one of them
cannot be paid, and hands a griefer a cheap denial of service.

Credit a ledger, let each payee withdraw their own:
[`x/daily/pullpayment`](./p/moul/x/daily/pullpayment) is the pattern with the reentrancy
already handled (`Withdraw` zeroes the balance before it returns the amount) and the
overflow guards already written.

### 4.4 Formatting an amount

[`p/moul/kit/num`](./p/moul/kit/num). It exists because there were six hand-rolled amount
formatters in this repository and two of them emitted `-1.-5` for a negative value: the
sign has to be carried on the whole part, so `Dec(-1, 6)` is `"-0.000001"` and not
`"0.999999"`.

### 4.5 Rounding is the money question

`xmath.MulDiv(a, b, c)` computes `a*b/c` with an intermediate that does not have to fit in
an `int64`, and **refuses rather than returning a wrong number** when the result does not
fit. `MulDivUp` is the same rounding away from zero.

Which direction you round is not a detail: round in the protocol's favour on the way in and
the user's favour on the way out, or state plainly which one you chose, because the
difference is where every AMM rounding exploit lives.

Splitting an amount N ways so the parts add back up to the whole is
[`x/games/prorata`](./p/moul/x/games/prorata). Exact rational arithmetic, when integers
genuinely will not do, is [`x/daily/fraction`](./p/moul/x/daily/fraction).

### 4.6 Vesting is a chain rule, not your rule

[`p/moul/vesting`](./p/moul/vesting) is not a vesting scheme of its own. It is a faithful
reimplementation of tm2's `std.VestingSchedule`, the curve **the gno.land chain itself
enforces**, so a realm can answer "how much of this balance can actually move right now"
before it tries to move it. `Spendable(balance, now)` is the function you want.

Your own cliff-then-linear schedule, for a grant you are running yourself, is
[`x/daily/cliffvesting`](./p/moul/x/daily/cliffvesting).

---

## 5. Authority: who is allowed to do this

### 5.1 The caller is `cur.Previous()` and nothing else

In a crossing function, the caller is derived from the realm token you were handed, and the
token has to be checked first:

```gno
func caller(cur realm) address {
	if !cur.IsCurrent() {
		panic("spoofed realm")
	}
	return cur.Previous().Address()
}
```

`IsCurrent()` before `Previous()`, every time. This is the shape
[`r/moul/forge`](./r/moul/forge) uses and it is the one the upstream audit-pattern harness
checks for.

**Three ways to get the caller that are wrong, in decreasing order of how obviously:**

- **`OriginCaller()` as an identity.** It is the transaction signer, not your caller, so any
  realm the user calls can turn around and act as them against you. This is the on-chain
  version of the confused deputy and it is the classic gno phishing vector. It is
  legitimate for exactly one thing: telling a user call apart from a realm call.
- **`unsafe.PreviousRealm()` in a realm that declares crossing functions.** You already
  have `cur`. Reaching around it means the check moved somewhere nothing verifies.
- **A read with no `cur realm` sees the *caller* as `unsafe.CurrentRealm()`, not itself.**
  Such a function is borrowed: gno opens no realm frame for it. That is what makes a
  zero-argument helper on a shared config realm possible at all, and it **reverses silently
  the moment the function grows a `cur realm` parameter**. Measured 2026-09-22 from
  `r/moul/config/v1` called by a realm at `gno.land/r/test/caller`:
  `CurrentRealm=gno.land/r/test/caller`, `PreviousRealm=gno.land/r/moul/config/v1`. Never
  branch on it for authorisation in either direction.

### 5.2 One owner, or a set of them

| you need | use |
|---|---|
| a single owner, transferable | `p/nt/ownable` |
| a member set, with the authority itself replaceable later | [`p/moul/authz`](./p/moul/authz) |

[`p/moul/authz`](./p/moul/authz) is the one to reach for when you do not yet know who will
own this in a year. The realm holds an `*Authorizer` and asks it to run privileged actions;
the `Authority` behind it starts as a `MemberAuthority` (a set of addresses) and can be
`Transfer`ed to a `ContractAuthority`, that is, to a DAO realm, without the realm that uses
it changing a line:

```gno
var auth = authz.NewWithMembers(deployer)

func SetFee(cur realm, bps int64) {
	if err := auth.DoByPrevious(0, cur, "set-fee", func() error {
		fee = bps
		return nil
	}); err != nil {
		panic(err)
	}
}
```

Note the `_ int, rlm realm` shape on `DoByPrevious`: a `p/` package may not declare a
crossing function, so the realm token is threaded as a later parameter. That is the same
shape `p/nt/grc20`'s tellers use and you will write it yourself in any `p/` that needs the
caller.

### 5.3 Authority by package path

Sometimes the question is not "is the caller this address" but "is the caller inside my
namespace". [`p/moul/nestedpkg`](./p/moul/nestedpkg):

```gno
nestedpkg.AssertCallerIsSubPath(0, cur)     // only realms below me
nestedpkg.AssertIsSameNamespace(0, cur)     // only realms under the same user or org
```

`IsCallerSubPath`, `IsCallerParentPath` and `IsSameNamespace` are the non-aborting forms.
This is how a suite of realms under one path trusts itself without maintaining an address
allowlist that drifts.

### 5.4 A pause switch

[`p/moul/pausable`](./p/moul/pausable) holds no state and knows nothing about where your
pause setting is stored. It is the parsed state, the rule for combining two of them, and
the asserts:

```gno
st := pausable.MustParse(cfg)   // fails closed on anything it cannot parse
st.AssertWritable()             // aborts when paused
```

`Strictest(a, b)` is the combinator, for a realm that respects both its own switch and a
global one. `MustParse` failing closed is the design decision worth copying: an
unparseable pause setting means paused.

### 5.5 Collective decisions

[`p/moul/udao`](./p/moul/udao) is the minimal DAO interface, deliberately written from the
outside: no members, no votes, because those differ per DAO and a non-member cannot act on
them anyway.

[`p/moul/grants`](./p/moul/grants) is a complete grant program as a pure package: anyone
asks the board for money, members vote in the open, and the money leaves in tranches that
each have to be earned by a proof the members accept. It is the largest worked example here
of "the whole domain in a `p/`, the chain wiring in an `r/`".

For a chain-level vote, you are not writing this: you are writing a proposal against
`r/gov/dao`.

### 5.6 Powers installed after the fact: `pilot`

[`p/moul/pilot`](./p/moul/pilot) is the gno answer to a Gnosis Safe with modules. **One
realm holds the funds and the identity, a key pilots it, and its powers arrive afterwards
as separate realms it never imports.**

The account keeps a `*Pilot` private and hands each module a narrow `Account` handle.
Everything privileged stays on `*Pilot`, which is never returned, so a module can only
reach the two methods it was given. Two ways to delegate, differing in exactly one
property:

- a **`Purse` is revocable**: every method re-enters the declaring package and re-checks
  the live roster and budget, so `Revoke` and `SetBudget` take effect immediately, even on
  a purse a module kept.
- a **sub-identity token is permanent**: it lets the module act as `<account>#<subpath>`
  toward any other realm, which a purse cannot do, but the module can mint a banker from it
  and keep it forever. Removing the module does not take that back. **Grant one only to
  code you have read.**

### 5.7 The anti-pattern list

These are the families the upstream [audit pattern
harness](https://github.com/gnolang/gno/tree/master/misc/audit-pattern-harness) scans for,
which is the closest thing the ecosystem has to a lint for this. Each one is a real finding
shape, not a style preference.

**This repository runs them on every pull request** (`make audit-patterns`), against a
ratcheting baseline: a count that goes up fails, and a count that goes down fails too and
asks to be re-recorded, so the debt can only shrink. The rules are mirrored verbatim in
[`tools/auditpattern`](./tools/auditpattern), because upstream's package is `internal/` in a
module of its own.

| pattern | why it is a finding |
|---|---|
| `cur.Previous()` without `cur.IsCurrent()` | the realm token was never checked |
| `OriginCaller()` used as an authorization identity | confused deputy, §5.1 |
| `OriginSend()` without an `IsUserCall()` guard | the envelope is not yours to read, §4.2 |
| raw caller markdown in `Render` | §3.3 |
| `Render` output that depends on map iteration order | insertion order is not a sort, §2.9 |
| a caller-supplied callback accepted by a realm API | you just gave an attacker your frame |
| an interface that exposes `cur realm` | the token escapes the package that checked it |
| an exported pointer, or pointer getter, to mutable state | a live mutation handle, no checks |
| an exported `*avl.Tree` field, var or return | the same, and the commonest shape of it |
| `unsafe.PreviousRealm()` in a realm with crossing functions | §5.1 |

**A hit is a line to read, not a proven bug.** Every rule is a lexical approximation and
several are generous on purpose, because a scanner that misses is worse than one that asks.
Eight of the ten are scanned in `r/` only, which is upstream's own framing ("accepted by a
realm", "returned from a realm"): a `p/` iterator taking a callback and a `p/` constructor
returning a pointer are those packages doing their job. `current_guard` and
`interface_realm_param` are scanned everywhere, because a `p/` that threads `rlm realm` has
exactly the question the first one asks, and an interface leaking `cur realm` is worst where
the interfaces live.

---

## 6. Time, height and randomness

### 6.1 Height is the clock you can trust

`runtime.ChainHeight()` is monotonic, agreed by consensus, and the only clock a realm
should schedule on. `time.Now()` in a realm is the block timestamp, which is agreed too but
is set by proposers and is not something to build a cliff out of at second resolution.

Prefer the shape where your pure package takes the tick as an argument and the realm
supplies it. That is what makes the logic testable at all:
[`x/daily/ratelimit`](./p/moul/x/daily/ratelimit) is `golang.org/x/time/rate` with the wall
clock replaced by a caller-supplied monotonic tick, and
[`x/games/clock`](./p/moul/x/games/clock) is a deadline that actions push forward and that
still ends. [`x/games/accrual`](./p/moul/x/games/accrual) is stock that fills at a rate
while nobody is playing, which is the same idea aimed at a game.

### 6.2 Both clocks reset in tests

Every test function starts at height **123** and at timestamp **1234567890** (2009-02-13),
and only *realm state* carries over between them. `testing.SkipHeights` is relative,
`testing.SetHeight` is absolute and moves backwards as happily as forwards, and there is no
height *reader* in `testing`: ask the chain with `runtime.ChainHeight()`.

The trap that costs an afternoon: a realm that stores a timestamp, seeded in a test at a
hand-picked "realistic" unix second, and every later call reading `time.Now()` sees a clock
fifteen years behind the state it is being asked about. It surfaces as a time-went-backwards
error from whatever does the arithmetic, and says nothing about tests.

**Drive the pure helpers with an explicit `at` argument and any constant you like. Anchor
anything that reaches `time.Now()` at `time.Now()`.**

### 6.3 Randomness does not exist here

Every input a realm can see is known to whoever submits the transaction, and the block
proposer sees more than that. [`p/moul/entropy`](./p/moul/entropy) gives you a cheap,
deterministic pseudo-entropy source seeded from height, time and caller. It is the right
tool for a demo, a cosmetic shuffle or an avatar. **It is never the right tool for anything
with money on it.**

When the outcome has value, make the participants commit first and reveal after:
[`x/daily/commitreveal`](./p/moul/x/daily/commitreveal), whose `MinSaltLen` exists because
a commitment without enough salt is a one-line brute force.

---

## 7. Errors, panics and aborts

Upstream's "embrace `panic`" is right, and this is the local refinement of it.

- **A `p/` package returns errors.** It does not know the caller's policy, and a caller that
  wants to abort can. [`p/moul/errs`](./p/moul/errs) combines several into one when a
  validation pass produces more than one failure.
- **A realm's crossing function aborts.** There is no transaction to half-apply: either the
  call was allowed and it happened, or it was not and nothing did. Abort with a message that
  names the thing, not the condition: `"game #7 not found"`, not `"not found"`.
- **`recover()` cannot catch a panic from a crossing call.** A panic raised across
  `cross(cur)` is a realm abort, and a `defer`/`recover()` in the caller never fires, even
  from the realm's own package. This is a language property, not a bug, and it is also why
  the assertion helper for it is `uassert.AbortsWithMessage` and not `uassert.PanicsWith`.
- **A panic can carry a non-string.** `banker.SendCoins`'s refusal panics with an `address`,
  because in gno a string concatenated with a named string type takes that type, so
  `uassert.PanicsContains` reports `recover: unsupported type` and reads nothing. Anything
  panicking with a value derived from an `address` or a `chain.Coin` denom has that shape;
  catch it with a hand-written `recover()` carrying a `case address:` arm.

---

## 8. Testing

Three things a gno test has to do that a Go test does not.

**1. Pin `Render`.** A realm's `Render` is its whole public surface, and an in-package
example test is the cheapest lock there is:

```gno
func ExampleRender() {
	print(Render(""))
	// Output:
	// …
}
```

Use the builtin `print`, which is captured on stdout and needs no import. **The `// Output:`
block is required**: an example without one is silently skipped, which reads exactly like a
passing test. And only a recent gno validates examples at all, so a canary package whose
pinned output is deliberately wrong, and which must therefore fail, is what tells you your
toolchain is not blind ([`make toolcheck`](./Makefile) here).

Two consecutive blank lines can never be pinned by an example, because gno collapses them
in an `// Output:` block exactly as Go does, and a lot of markdown `Render`s produce them.
Assert those with `uassert.Equal` and a backtick literal instead.

**2. Switch accounts inline.** `testing.SetRealm` only governs the crossing calls made from
the frame that called it. Call it inside a test helper that does not itself cross and it is
silently ignored, the caller stays whoever it was, and that surfaces much later as
`cannot send transfer to self` or a balance credited to nobody. A helper that crosses right
afterwards *does* work, which is what makes this hard to spot. Switch accounts in the test
body.

**3. Assert a refusal, not a panic.**

```gno
uassert.AbortsWithMessage(t, cur, "stale ref", func() { SetRef(cross(cur), …) })
```

The argument is a no-arg closure that crosses with the outer `cur`. With a `func(realm)`
the helper does its own `cross(rlm)` first, which consumes the pending `testing.SetRealm`,
so the abort under test runs with the realm itself as caller and every authorization
assertion fails with `unauthorized` instead of the error you meant to pin.

**And the rule that makes all three worth anything: a test that passes is not evidence
until you have seen it fail.** Break the thing it covers, confirm it goes red, restore. A
test that *cannot* fail reads exactly like a test that is satisfied.

Two more shapes worth knowing: **realm globals persist for the whole test binary and
examples run after every `Test`**, so an `ExampleRender` sees the state the tests left and
must reset what it renders first; and **the bank does not carry over between test functions
though realm state does**, so a realm's own view and the chain's can be made to disagree by
nothing more than a test boundary. Assert balances in the test that created them, and
assert deltas rather than totals.

---

## 9. Cost: gas, storage deposit and the deploy

### 9.1 Gas is a fixed cost plus a per-byte cost

Over 464 successful mainnet `add_package` transactions the fit is

```
gas ~= 3,800,000 + 1,285 * bytes
```

with gas per byte ranging 989 to 16,435. **Sizing a deploy from bytes alone is wrong rather
than merely tight**: every deployment pays to be parsed, type-checked and initialised before
the first source byte is charged for. A flat `1800/byte` under-funded 37% of that history
and killed an 83-package run on a 4 KB package.

Do not hand-write a gas number. Simulate, then size from what the chain reported.

### 9.2 Storage deposit is locked, not spent

Every byte of realm state locks GNOT at the chain's `storage_price` (100 ugnot per byte by
default), and the lock is **refunded to whoever signs the transaction that frees the byte**,
not to whoever paid it. That is the whole economics of §2.12, and it makes "should I delete
this?" an arithmetic question rather than a hygiene one.

[`p/moul/x/storagecost`](./p/moul/x/storagecost) answers it: `Evaluate(bytes, pricePerByte,
gasWanted, num, den)` returns a `Quote` with a `Worth()`, `EstimateBytes` and
`EstimateNodes` size the input, and `BreakEvenBytes` tells you how many bytes a given fee
has to free before it pays for itself.

One asymmetry that is not obvious: a redeploy of a private realm **accumulates** deposit.
Prior objects are not evicted and nothing can free them, so each redeploy is charged in full
and refunds nothing.

### 9.3 The deploy itself

On mainnet, publishing is not immediate: a post-genesis `MsgAddPackage` parks until an
approvals oracle clears it, so a publish that "succeeds" is queued, not live. And paths
there are permanent, which is the reason §1.2 and §1.3 are as strict as they are.

The tooling here is [gnopm](https://github.com/moul/gnopm), driven by `make publish`: it
asks the chain what is missing, orders it by dependency and signs **once per dependency
layer**, not once per package. It holds no key and signs nothing itself.

---

## 10. Do not hand-roll this

The index of things this repository has written more than once, with the one place they now
live. If you are about to write a helper, look here first.

| you were about to write | it exists |
|---|---|
| a markdown table, by concatenating strings | [`kit/ui`](./p/moul/kit/ui) `NewTable` |
| `min`, `max`, `clamp`, `abs`, `sign` for a numeric type | [`xmath`](./p/moul/xmath), one concrete function per type |
| `a*b/c` that might overflow halfway | [`xmath`](./p/moul/xmath) `MulDiv`, `MulDivUp` |
| an amount formatter for ugnot | [`kit/num`](./p/moul/kit/num) |
| a zero-padding helper, because `ufmt` has no width flags | [`kit/num`](./p/moul/kit/num) `Pad` |
| an auto-incrementing id plus a padded avl key | [`kit/store`](./p/moul/kit/store) |
| a `key -> id` lookup beside a store | [`kit/index`](./p/moul/kit/index) |
| a `Len`/`Swap`/`Less` for a leaderboard | [`kit/tally`](./p/moul/kit/tally) |
| a query-string parser for `Render` | [`realmpath`](./p/moul/realmpath) |
| a page picker | [`pageable`](./p/moul/pageable), or `kit/store`'s `Page` |
| a `$help&func=` URL | [`txlink`](./p/moul/txlink), [`helplink`](./p/moul/helplink), `ui.Action` |
| an address shortener | [`kit/ui`](./p/moul/kit/ui) `Addr`, `Short`, `ShortN` |
| a "nothing here yet" line | [`kit/ui`](./p/moul/kit/ui) `Empty`, `Table.OrEmpty` |
| a bytes / ordinal / plural formatter | [`x/daily/humanize`](./p/moul/x/daily/humanize) |
| a set of addresses | [`addrset`](./p/moul/addrset) |
| a template with `{{ }}` | [`template`](./p/moul/template), or [`dynreplacer`](./p/moul/dynreplacer) |
| map / filter / reduce over `[]any` | [`fp`](./p/moul/fp) |
| a "convert anything to a string" helper | [`typeutil`](./p/moul/typeutil) |
| a multi-error | [`errs`](./p/moul/errs) |
| base58, base32, crc32, a Merkle proof, semver | [`x/daily/*`](./README.md#contracts), [`x/merkle`](./p/moul/x/merkle) |
| a reaction bar under a page | [`reactions`](./p/moul/reactions) |
| a one-time init guard | [`once`](./p/moul/once) |
| an SVG | [`svg`](./p/moul/svg) |

And the three marked 🚧, which are declared but **not implemented**, so do not import them
expecting behaviour: [`entity`](./p/moul/entity), [`ownable`](./p/moul/ownable) (use
`p/nt/ownable`), [`safe`](./p/moul/safe), and [`xdao`](./p/moul/xdao) is partial.

---

## Upstream reading

Read these. This file is the layer above them, not a replacement, and where it disagrees
with one it says so and shows the measurement.

| when | read |
|---|---|
| before anything else | [Effective Gno](https://docs.gno.land/resources/effective-gno/) |
| you are unsure what a realm even is | [Realms](https://docs.gno.land/resources/realms/) |
| you are choosing a data structure | [Gno data structures](https://docs.gno.land/resources/gno-data-structures/), then §2 here |
| you are writing a crossing function | [Interrealm specification](https://docs.gno.land/resources/gno-interrealm/) |
| you hit a "this works in Go" wall | [Go/Gno compatibility](https://docs.gno.land/resources/go-gno-compatibility/), [Gno memory model](https://docs.gno.land/resources/gno-memory-model/) |
| you are writing tests | [Testing gno code](https://docs.gno.land/resources/gno-testing/) |
| you are about to deploy | [Gas fees](https://docs.gno.land/resources/gas-fees/), [Storage deposit](https://docs.gno.land/resources/storage-deposit/) |
| you are reviewing somebody's contract | [Security guide](https://docs.gno.land/resources/gno-security-guide/), and the [audit pattern harness](https://github.com/gnolang/gno/tree/master/misc/audit-pattern-harness) |
| you want the stdlib list | [Gno standard libraries](https://docs.gno.land/resources/gno-stdlibs/) |

---

## Corrections

Every number here was measured, and each one carries the date and what it was measured
against. If one is wrong, the fix is a pull request that changes the number **and** says how
it was re-measured, not one that softens the sentence. If a recipe points at a package that
turns out to be the wrong answer, say so in the row rather than deleting it: the reason
somebody reached for it is the useful part.

Everything here is MIT, and the disclaimer in [DISCLAIMER.md](./DISCLAIMER.md) applies:
these are personal contracts, most of them unaudited, several of them explicitly
experimental. Read the code before you import it.
