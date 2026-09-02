# `gno.land/p/moul/x/daily/rle/v1`

**Run-length encoding** — `Encode`, `Decode`, `Ratio`, `MaxLen`.

Runs of a repeated byte collapse to `<count><char>`, counts in decimal:
`"aaabbc"` → `"3a2b1c"`.

```go
import "gno.land/p/moul/x/daily/rle/v1"

rle.Encode("aaabbc")   // "3a2b1c", nil
rle.Decode("3a2b1c")   // "aaabbc", nil
rle.Ratio("abcdef", "1a1b1c1d1e1f")  // 200 — bigger than the input!
```

**Every run carries a count, including runs of one.** A uniform grammar is
cheaper to decode and impossible to get subtly wrong, at the cost of expanding
data that has no runs. That trade is deliberate and visible: `Ratio` returns
over 100 when the "compression" grew the data, because **RLE only wins on runny
input** and pretending otherwise would be dishonest.

**Digits are rejected** by `Encode` — in the output they would be
indistinguishable from a run count, so a round-trip would silently return the
wrong string. Better to refuse.

`Decode` bounds the *expanded* size too, not just its input: `"999999x"` is
seven bytes that would otherwise become a megabyte.

**Live demo:** [`r/moul/x/daily/rledemo`](https://github.com/moul/gno-contracts/tree/main/r/moul/x/daily/rledemo/v1)
· render it at [`/r/moul/x/daily/rledemo/v1`](https://gno.land/r/moul/x/daily/rledemo/v1).
