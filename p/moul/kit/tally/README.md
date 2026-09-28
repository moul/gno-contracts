# `gno.land/p/moul/kit/tally`

Order a scoreboard: highest score first, ties broken by key.

Fourth package of the `p/moul/kit/*` layer
([moul/gno-contracts#151](https://github.com/moul/gno-contracts/issues/151)), after
[`ui`](../ui), [`store`](../store) and [`num`](../num). `kit` composes the existing
packages, it does not replace them.

## Why it exists

gno has **no `sort.Slice`**. Ordering anything therefore needs a named type with
`Len`, `Less` and `Swap`, so every realm that shows a leaderboard writes one.

Measured on `main`, 2026-09-28: **16 packages carry their own `sort.Interface`
triple.** They are not all the same shape, so here is the honest split, by how
many score clauses the comparator has before its final return:

| shape | packages | fits this package? |
|---|---|---|
| **one score, then a tie-break** | `kudos`, `leaderboard`, `multiset`, `pixelcanvas`, `prorata`, `reactions`, `streak`, `tamagotchi` | **yes, 8 of the 16** |
| two scores, then a tie-break | `collatz`, `idle`, `kingofdice`, `rpgroom`, `streaks`, `tipjar` | no |
| not a scoreboard | `eggling`, `semverdemo` | no |

So this package targets **8**, and it says so rather than claiming 16. A
two-score board (`idle` ranks on prestige, then lifetime, then owner) has a
genuinely domain-specific comparator, and flattening it into one `int64` would
be a worse API than the triple it replaced.

## What the 16 disagree on: the tie

The final clause of `Less` is what decides two equal scores, and it is the
clause everyone writes differently:

| final clause | realms |
|---|---|
| the key, as `addr.String()` | `idle`, `kingofdice`, `leaderboard`, `streaks`, `tamagotchi`, `tipjar` |
| the key, as a bare string | `kudos`, `pixelcanvas`, `streak` |
| a domain field (`Elem`, `N`, `emoji`, `index`) | `multiset`, `collatz`, `reactions`, `prorata` |
| **the score again** | **`rpgroom`** |

`rpgroom`'s third clause is `return r[i].Kills > r[j].Kills`, after `Level` and
`XP`. That is **not a total order**: two heroes equal on all three compare
`false` in both directions, so their order is whatever the sort algorithm did
with the input. It is reproducible (`heroes.Iterate` walks an avl tree, and
`sort.Sort` is deterministic), so this is not a consensus bug, but nobody chose
that order and nothing pins it.

`Sort` always ends on `Key`, so the answer is the same one every time and it is
explicable to a reader.

## What is here

| | |
|---|---|
| `Sort(entries)` | in place, highest first, ties by key |
| `Top(entries, n)` | the n highest, **copied**, so the caller's slice is untouched |
| `Rank(entries, key)` | 1-based, `0` if absent, and **never a tie**: equal scores still get distinct places |
| `Board` | `NewBoard`, `Add`, `Set`, `Score`, `Has`, `Remove`, `Len`, `Entries`, `Top`, `Rank` |

Two entry points on purpose. The 16 above already own their state and adopt by
mapping it to `[]Entry`; a realm starting fresh reaches for `Board` and gets the
storage too.

`Board` is backed by an **avl tree, not a map**. gno map iteration order is
unspecified, so a `Render` built by ranging a map is not reproducible.
`TestBoardOrderDoesNotDependOnInsertion` pins it.

## What is deliberately not here

- **Rendering.** A podium, a table and address shortening belong to
  [`kit/ui`](../ui). This package returns rows.
- **Scores that are not `int64`.** Nothing on chain ranks by a float, and gno
  has no float determinism worth relying on for consensus output.
- **Stable sort.** `Sort` is a total order, so stability is not observable.
