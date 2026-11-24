# `gno.land/r/moul/x/daily/manacherdemo/v0`

**Live demo of [`p/moul/x/daily/manacher`](https://github.com/moul/gno-contracts/tree/main/p/moul/x/daily/manacher).**

A thin, stateless realm: it holds no state of its own and contains none of the
library's logic. `Render` walks the radius of every centre of one worked word,
answers the longest-palindromic-substring question for a handful of inputs
including the one that kills a naive scan, and shows why the interleaving
separator needs no reserved value.

Because it is stateless, the rendered page is identical on every call and on
every node, which is what lets an example test pin it byte for byte.

Render it at [`/r/moul/x/daily/manacherdemo/v0`](https://gno.land/r/moul/x/daily/manacherdemo/v0).

The library README explains the design and the trade-offs; this realm is the
worked example.
