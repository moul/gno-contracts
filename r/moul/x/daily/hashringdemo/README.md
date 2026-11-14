# `gno.land/r/moul/x/daily/hashringdemo/v0`

**A gnoweb demo of [`p/moul/x/daily/hashring`](/p/moul/x/daily/hashring/v0)**: where keys
land, what it costs to lose a node, no state, no placement logic of its own.

```
/r/moul/x/daily/hashringdemo/v0         the ring, the shares, and the migration cost
/r/moul/x/daily/hashringdemo/v0:/hello  place your own key and show its preference list
```

**The third table is the whole page.** Four nodes, 2,000 keys, then `gamma` is taken out and
the same keys are placed again. Consistent hashing moves 517 of them; `hash(key) % n` moves
1,463. The 517 is the floor, the keys that lived on the departed node and have nowhere else
to be, and the ring pays exactly it. The modulo shard pays it and then moves 946 keys that
had nothing wrong with where they were.

Both numbers are computed in `Render`, against the same key set, on every call. They are a
measurement rather than a worked example in prose, which is why the realm builds the modulo
placement too instead of quoting a figure at the reader.

**Fixed inputs, never chain state, deliberately.** Every value rendered here is a package
level variable. Output that moved with the block height could not be pinned by
`ExampleRender`, and an unpinned `Render` is how a realm ships a page nobody ever read.

**The visitor's key reaches the page once, inside a code span**, through `md.InlineCode` and
not `ui.Cell`: a cell escaper backslashes a backtick, and a backslash does not close a
backtick inside a span, so only a fence wider than anything in the argument does, which is
what `md.InlineCode` picks. Every table cell holds a derived value, a hash or a node name
from this realm's own fixed membership. A realm's `Render` can never be fixed once the path
is live.

The share column is integer arithmetic to one decimal place. A float here would be a
rounding question nobody asked, on a page whose whole point is a count.

Built for gno 0.9.
