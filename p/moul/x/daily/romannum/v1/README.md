# `gno.land/p/moul/x/daily/romannum/v1`

**Roman-numeral converter** — `ToRoman`, `FromRoman`.

A pure port of the classic kata, valid for **1..3999**. `ToRoman` uses greedy
subtractive notation (panics out of range); `FromRoman` accepts a numeral only
if it is canonical (it must round-trip through `ToRoman`), so malformed forms
like `IIII`, `VV`, or `IC` are rejected. Deterministic — no time, randomness, or
I/O — and free of any realm coupling.

```go
import "gno.land/p/moul/x/daily/romannum/v1"

s := romannum.ToRoman(2024) // "MMXXIV"
n := romannum.FromRoman(s)   // 2024 (panics on a malformed numeral)
```

**Live demo:** [`r/moul/x/daily/romannumdemo`](https://github.com/moul/gno-contracts/tree/main/r/moul/x/daily/romannumdemo/v1)
· render it at [`/r/moul/x/daily/romannumdemo/v1`](https://gno.land/r/moul/x/daily/romannumdemo/v1).
