# `gno.land/p/moul/x/daily/hilbert/v0`

**The Hilbert curve: a point on a square grid as one number, and back**, with
`Encode`, `Decode`, `Ranges`, `Side` and `Length`.

```go
import "gno.land/p/moul/x/daily/hilbert/v0"

d, _ := hilbert.Encode(16, 20000, 20000)       // 547883008, the key you store
x, y, _ := hilbert.Decode(16, d)               // 20000, 20000
rs, _ := hilbert.Ranges(16, 20000, 20000, 20015, 20015)
// one Range: 547883008 .. 547883263, so one tree.Iterate covers the window
```

A realm has exactly one cheap index, an avl tree over a single key, and a map
of anything is two-dimensional. Flattening the grid is how you get a spatial
query out of a tree that only understands order, and which flattening you pick
decides what a window costs.

**It is the curve with no jumps, deliberately.** Interleaving the bits of x and
y, which is what a geohash does, also turns a point into one number, and it
leaps across the grid at every power-of-two boundary: two touching cells land
at opposite ends of the key space. This curve never leaves a neighbourhood
before it has finished it. Consecutive indices are always neighbouring cells,
and every aligned sub-square is one unbroken run of indices, which is the
property `Ranges` is built on.

Three behaviours worth knowing before you use it:

- **`Ranges` costs the area of the box, not its perimeter.** It walks every
  cell, so it refuses a box above `MaxBoxCells` (65536) with `ErrTooLarge`
  rather than serving it slowly. A big grid wants a coarse order for the key
  and a finer coordinate inside the value, not one order fine enough to need a
  huge box.
- **A run is tight in both directions.** Scanning everything `Ranges` returns
  visits the cells of the box and nothing else, so there is no filter pass
  afterwards and no cell missed. The runs come back ascending, disjoint, and
  never touching, since two touching runs are one scan.
- **An off-grid coordinate is refused, never clamped.** `ErrPoint` rather than
  a wrapped key, because a silently clamped point becomes a wrong key that
  nothing downstream can detect.

**It is not always better than `y*side + x`, and the crossover is the size of
the window against the grid.** A row-major key puts one row beside the next, so
a window 16 rows tall always spans 15 whole rows of key space however narrow it
is. Measured at order 16, a 16x16 window at (20000, 20000) is **1 run spanning
256 keys** against row-major's **16 runs spanning 983,056**. Measured at order
4, where the window is a third of the grid, the window (5,5)-(10,10) is **9
runs** against row-major's **6**. The curve pays off when the window is small
against the grid, which is the case a spatial index exists for.

Order 31 is the last one that fits: a 2,147,483,648-cell side in a `uint32` and
a 4-quintillion-cell curve in a `uint64`. Everything is integer arithmetic on
powers of two, so nothing is rounded and two identical calls cannot disagree,
which is the bar a `Render` has to clear.

The curve is the published iterative construction, ported as is. It was checked
cell by cell against a second, recursive construction over all 65,536 cells of
order 8 before being written down, so the golden table in the test is not this
package marking its own homework.

Not included: a rectangle decomposition that is output-sensitive rather than
area-proportional, the 3-D curve, or a nearest-neighbour search. `Ranges` and
the index are the primitives those would be built on.

**Live demo:** [`r/moul/x/daily/hilbertdemo`](https://github.com/moul/gno-contracts/tree/main/r/moul/x/daily/hilbertdemo)
· render it at [`/r/moul/x/daily/hilbertdemo/v0`](https://gno.land/r/moul/x/daily/hilbertdemo/v0).
