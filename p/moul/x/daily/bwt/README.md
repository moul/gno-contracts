# `gno.land/p/moul/x/daily/bwt/v0`

**Burrows-Wheeler transform**: `Transform`, `Inverse`, `Matrix`, `Runs`, `MaxLen`, `MaxMatrixLen`.

A reversible permutation that groups equal bytes together. It compresses
nothing on its own: the output holds the same bytes as the input, in a
different order, plus the one integer needed to undo it.

```go
import "gno.land/p/moul/x/daily/bwt/v0"

last, idx, _ := bwt.Transform("banana")   // "nnbaaa", 3
bwt.Inverse(last, idx)                    // "banana", nil
bwt.Runs("banana"), bwt.Runs(last)        // 6, 3 : that is the whole point
```

This exists as a **preprocessing step**, not a codec. bzip2 runs it before
move-to-front and Huffman, and the clustering is where the ratio comes from:
a run-length coder is paid by run length, and sorting every rotation of the
input puts the bytes that follow similar context next to each other.

**It returns an index instead of appending a sentinel, deliberately.** The
textbook version appends a byte that sorts before everything and never appears
in the input, which removes the need for an index. There is no such byte in an
arbitrary string, so that version can only transform data whose alphabet you
already control. The index costs one integer and the alphabet stays closed:
`Transform` output is a permutation of its input, so nothing downstream has to
widen.

Four behaviours worth knowing before you use it:

- **The clustering is a tendency, never a guarantee.** `Runs` is exported so a
  caller can measure rather than assume. `"banana bandana bandanna"` drops from
  22 runs to 11; `"mississippi"` does not move at all, because it repeats
  letters but no substring long enough to group. A caller that applies the
  transform unconditionally will sometimes pay for nothing.
- **The cost is quadratic in the input.** Sorting the rotations takes
  O(n log n) comparisons and a comparison walks up to n bytes. `MaxLen` is
  **256** for that reason, and the degenerate input that reaches the worst case
  (`"aaaa..."`) is the one a caller is most likely to try first. Rotations are
  compared in place by offset, never materialised, so the memory is O(n).
- **`Inverse` is O(n) and never rebuilds the matrix.** The first column is the
  last one sorted, and the *i*-th occurrence of a byte in the last column is
  the *i*-th occurrence of it in the first. That is enough to walk the original
  backwards one byte at a time.
- **`Matrix` is a teaching aid with its own, much smaller bound.** It
  materialises every rotation, so it allocates n squared bytes;
  `MaxMatrixLen` is 64. Its last column is exactly what `Transform` returns,
  and a test pins that, but no caller should reach for it to get a result.

Round-tripping is total within `MaxLen`: every string `Transform` accepts comes
back from `Inverse` unchanged, including the empty string, a string of one
repeated byte, and bytes outside ASCII. `Inverse` validates the index rather
than walking off the end of the column it was handed, because that index
arrives from a caller.

**Live demo:** [`r/moul/x/daily/bwtdemo`](https://github.com/moul/gno-contracts/tree/main/r/moul/x/daily/bwtdemo)
· render it at [`/r/moul/x/daily/bwtdemo/v0`](https://gno.land/r/moul/x/daily/bwtdemo/v0).
