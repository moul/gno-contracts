# `gno.land/r/moul/x/daily/hilbertdemo/v0`

**A gnoweb demo of [`p/moul/x/daily/hilbert`](https://github.com/moul/gno-contracts/tree/main/p/moul/x/daily/hilbert)**,
the space-filling curve library. Three read-only pages, no state, no caller
input.

| path | shows |
|---|---|
| `/` | the order 3 curve drawn with its index in every cell, so the no-jump property is visible |
| `/box` | an 8x8 box on a 16x16 grid, and the six index runs it becomes |
| `/keys` | the same question at order 16, against a row-major key |

It contains no curve logic of its own: every index and every run on the page
comes from the library. The one exception is the row-major baseline on
`/keys`, which is the thing being compared against and deliberately not part of
the library. `Render` takes nothing from a caller and reads no clock, height or
balance, so all three pages are pinned exactly by `ExampleRender` tests.

The page worth reading is `/keys`. A 16x16 window at (20000, 20000) is one run
of 256 keys, where a row-major key gives sixteen runs spanning 983,056. The
same table is also where the demo admits the curve loses: on a grid barely
bigger than the window, row-major wins, and the README of the library gives the
measured case.
