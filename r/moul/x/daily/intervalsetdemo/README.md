# `gno.land/r/moul/x/daily/intervalsetdemo/v0`

**Live demo of [`p/moul/x/daily/intervalset`](https://github.com/moul/gno-contracts/tree/main/p/moul/x/daily/intervalset)**:
half-open integer ranges kept sorted, disjoint and coalesced.

`Render` replays nine booking writes in the order they arrived and shows, after
each one, the span count, the covered length and the whole set. Nine writes end
as two spans, which is the argument: the storage tracks the shape of the data
rather than the number of times somebody wrote to it.

Three rows carry the page. Row 4 adds a range that only *touches* the previous
span and still merges. Row 7 adds a range already covered, and nothing happens
at all. Row 8 cancels from the middle, the one operation that can raise the span
count.

The last two sections contrast `Covers` with `Overlaps`, the two questions a
booking realm actually asks, and spell out what a plain slice of pairs gets
wrong, including the double-counted overlap that makes one wrong for billing.

It holds no interval logic of its own and no state at all, so `Render` is
deterministic and an example test pins it byte for byte.
