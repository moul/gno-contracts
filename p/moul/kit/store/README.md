# `gno.land/p/moul/kit/store/v0`

The auto-id ordered collection every `r/moul` realm was building by hand: an
`avl.Tree`, an int counter, and a private function that zero-pads the counter
into a key so the tree iterates in the order a human expects.

Second package of the `p/moul/kit/*` layer
([moul/gno-contracts#151](https://github.com/moul/gno-contracts/issues/151)).
`kit` composes the existing packages, it does not replace them.

## Why it exists

Sixteen realm files in this repo carry that third piece. They do not agree:

| Name | Width | Implementation | Realms |
|---|---|---|---|
| `padID` | 6 | `for len(s) < 6 { s = "0" + s }` | `asciiart` |
| `pad` | 12 | `for len(s) < 12 { s = "0" + s }` | `tictactoe` |
| `key` | 12 | the same loop, a different name | `blog`, `crowdfund`, `englishauction`, `erc721`, `splitter` |
| `idKey` | 12 | the same loop again, a third name | `connect4` |
| `idKey` | 12 | `strings.Repeat`, guarded by `len(s) >= width` | `governor`, `todos` |
| `idKey` | 12 | `strings.Repeat`, **unguarded** | `timecapsule` |
| `seqKey` | 16 | `strings.Repeat`, guarded | `guestbook` |

Five names, three widths, three implementations, one job, across 16 files in 12
realms.

**Every one of them is a silent ceiling.** The key is a decimal string, and
decimal strings do not sort numerically. Below the width the zero-padding hides
that; at the width the padding stops and the tree starts ordering
`"1000000000000"` before `"999999999999"`, so every list the realm renders is
wrong from that entry on. Nothing fails, nothing logs, the order is just quietly
false.

The unguarded variant fails harder. `strings.Repeat` panics on a negative count,
so past its width `timecapsule` stops accepting writes rather than mis-sorting
them.

`asciiart`'s width of 6 puts its ceiling at one million entries.

Both tests live in
[`store_test.gno`](./store_test.gno) (`TestOrderSurvivesThePaddingCeiling`,
`TestUnguardedPadPanicsPastItsWidth`), asserting the defect rather than
describing it.

## The fix is to delete the decision

Keys are the big-endian bytes of a
[`p/nt/seqid`](/p/nt/seqid/v0) ID: a fixed 8 bytes whose lexicographic order
**is** numeric order, for every value a `uint64` can hold. There is no width to
pick and no width to outgrow. `seqid` already solved this and was imported by
exactly one file in the repo.

```go
import "gno.land/p/moul/kit/store/v0"

var games = store.Named("game")             // or `var games store.Store`

func NewGame(cur realm) int64 {
    return int64(games.Add(&Game{Board: empty, X: caller()}))
}

func Move(cur realm, gameID int64, cell int) {
    g := games.MustGet(store.ID(gameID)).(*Game)   // panics "game #7 not found"
    ...
}

func Render(path string) string {
    for _, e := range games.PageReverse(1, 20) {   // newest first, one page
        g := e.Value.(*Game)
        ... e.ID ...
    }
}
```

## API

| | |
|---|---|
| `New()` | a new empty store; the zero `Store` works too |
| `Named("game")` | the same, with a noun for the `MustGet` panic |
| `Add(v) ID` | store under the next ID |
| `Set(id, v) bool` | write at an explicit ID, reports a replacement |
| `Get(id) (any, bool)` | value and presence, so a stored `nil` is not "absent" |
| `MustGet(id) any` | or panic `store: no entry #7`, or `game #7 not found` when named |
| `Has(id)`, `Remove(id)`, `Len()`, `LastID()` | |
| `Each(fn)`, `EachReverse(fn)` | every entry, ascending / descending |
| `EachUntil(fn) bool`, `EachReverseUntil(fn) bool` | stop when `fn` returns true |
| `Page(page, size) []Entry` | 1-based, ascending |
| `PageReverse(page, size) []Entry` | 1-based, newest first |
| `Pages(size) int` | for the pager footer |
| `ParseID(s) (ID, bool)`, `ID.String()`, `ID.Key()` | the path round trip |

### IDs stay plain integers

An `ID` is a `uint64` that renders as a decimal number, so a realm ported to
this package keeps showing `#7` exactly as it did. Only the avl key changes, and
the key was never user-visible.

IDs start at **1**, so the zero `ID` is usable as "absent" and `ParseID("0")`
rejects. Removing an entry does **not** free its ID: IDs are a history, not a
dense index, and reusing one would silently repoint an old link at a new object.

### Two iteration shapes, on purpose

`Each` takes no stop signal. It is the common case, and a callback whose `bool`
means "stop" reads identically to one whose `bool` means "continue", so the
wrong guess is invisible. When iteration has to end early the name says so:
`EachUntil`, where **true means stop**, matching `avl.IterCbFn` exactly. A
callback moved between this package and a raw tree keeps its meaning.

### Paging is 1-based and forgiving

Page numbers are shown to a reader ("page 1 of 4"), and an off-by-one between
the URL and the label is the bug this avoids. A page past the end, or a page or
size below 1, returns an empty slice rather than panicking, because the page
number usually arrives from a `Render` path and that is user input. Only the
requested window is walked, not the whole tree.

## Design rule

**The safe, conventional thing must be the shortest thing to type.** `Add` is
shorter than `nextID++` plus a padding function, and it cannot be got wrong.
That is the only mechanism that stops this helper from being written a
seventeenth time.

<!-- BEGIN GNOCONTRACTS FOOTER (generated by `make readmes`; do not edit below) -->

---

Part of **[moul/gno-contracts](https://github.com/moul/gno-contracts)** — moul's versioned gno.land contracts. See the repository for the full catalog, build/test tooling, and usage.

**Dependency graph:**

![gno.land/p/moul/kit/store/v0 dependency graph](https://raw.githubusercontent.com/moul/gno-contracts/main/_assets/gno.land/p/moul/kit/store/v0/deps.png)

> ⚠️ **Disclaimer:** provided as-is, without warranty; not security-audited. Full disclaimer: [DISCLAIMER](https://github.com/moul/gno-contracts/blob/main/DISCLAIMER.md).

<!-- END GNOCONTRACTS FOOTER -->
