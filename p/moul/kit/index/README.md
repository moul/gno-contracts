# index

The secondary index every realm with a store was writing by hand: a lookup from
a key a human typed to the [`store.ID`](../store)s that carry it.

```go
import (
	"gno.land/p/moul/kit/index/v0"
	"gno.land/p/moul/kit/store/v0"
)

var notes = store.Named("note")
var byTag index.Index // the zero value is an empty, usable index

func Post(cur realm, tag, body string) int64 {
	id := notes.Add(&note{Tag: tag, Body: body})
	if err := byTag.Add(tag, id); err != nil {
		panic(err) // the store write is not committed either: same frame
	}
	return int64(id)
}

func Render(path string) string {
	for _, e := range byTag.Page(1, 20) { // keys ascending, one page
		_, _ = e.Key, e.IDs
	}
	return ""
}
```

Fifth package of the `p/moul/kit/*` layer, after `ui`, `store`, `num` and
`tally`. Live demo: [`r/moul/x/kitindexdemo`](../../../../r/moul/x/kitindexdemo).

## What it is not

**Not a multi-index record store.** [`p/moul/collection`](../../collection) is
that, and measured at n = 1,000 an update there costs **964,833 gas against the
508,977** that created the record, because `Update` removes and re-adds every
index entry for every index whether or not the indexed value changed. Two
containers written side by side cost a third of that, and the realm can see what
it is paying for.

**Not a bound.** An index grows with the store it indexes. The realm owns the
bound, because only the realm knows what it is willing to pay a storage deposit
for.

## The three decisions worth knowing

**Backed by a B+ tree at fanout 128, not `avl` and not the package default of
32.** Measured against gno master `1fc4c140e` on 2026-09-29, n = 1,000, string
values:

| backing | bytes/entry | gas/insert |
|---|--:|--:|
| `bptree` fanout 128 | 592 | 152,975 |
| `bptree` fanout 32 | 671 | 162,161 |
| `avl` | 2,029 | 417,811 |

Raising the fanout amortises the node objects. Nothing below 592 is reachable:
the rest is the B+ tree's per-entry value box, which fanout cannot touch.

**The ids under a key are kept ascending, not in insertion order.** So `Lookup`
depends on the *set* of ids and not on the order they arrived in: two realms
that indexed the same records in a different order render identically. A
`Render` whose output depends on insertion history is a determinism bug, and
this is where it would have come from.

**`Lookup` and `Each` hand out a copy.** Returning the stored slice would make
every caller a writer: an assignment into it corrupts the index with no write
path having been called. A realm that passes the result onward is passing its
own data, not a handle to ours.

**The `Index` itself is a handle.** Its state sits behind one pointer, so a copy
taken after the first write (or of anything `Unique()` returned) is the same
index, and `Len` can never disagree with `Keys` about what it holds.

## API

| | |
|---|---|
| `New()`, `Unique()` | many ids per key, or at most one. The zero value is `New()` |
| `Add(key, id) error` | idempotent for the same pair; `ErrEmptyKey`, `ErrZeroID`, `ErrDuplicateKey` |
| `Remove(key, id) bool`, `RemoveKey(key) int` | a key whose last id goes is removed with it |
| `Lookup(key) []store.ID`, `First(key) (store.ID, bool)` | ascending; a copy |
| `Has`, `Count(key)`, `Keys()`, `Len()`, `IsUnique()` | `Keys` counts keys, `Len` counts pairs, and the difference is the fan-out |
| `Each(fn) bool` | ascending by key; true means stop, matching `bptree` and `kit/store`. `fn` must not write to the index |
| `Page(page, size) []Entry`, `Pages(size) int` | 1-based, every out-of-range page is nil (`kit/store`'s `Page` returns an empty slice instead), `Pages` is never 0 |

`Add` returns an error rather than aborting, because a `p/` package does not
know the caller's policy. In a realm the handling is almost always `panic(err)`:
every one of the three is a bug in the realm rather than a value a user chose.
