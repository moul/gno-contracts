# `gno.land/p/moul/x/daily/jarowinkler/v0`

**Jaro and Jaro-Winkler string similarity** (`Jaro`, `Winkler`, `WinklerTuned`,
`Explain`, `Percent`).

Where Levenshtein counts the edits between two strings, Jaro measures how much
of them lines up: how many runes match inside a sliding window, and how many of
those matches arrive out of order. Winkler then rewards a shared prefix, which
is what makes the pair the classic choice for names and short identifiers.
Ported from Go's `xrash/smetrics`, fully rune-aware and pure.

```go
import "gno.land/p/moul/x/daily/jarowinkler/v0"

jarowinkler.Jaro("MARTHA", "MARHTA")              // 944444, out of Scale (1e6)
jarowinkler.Winkler("MARTHA", "MARHTA")           // 961111
jarowinkler.Percent(961111)                       // "96.11%"
jarowinkler.WinklerTuned("CRATE", "TRACE", 0, 4)  // the two constants, exposed

s := jarowinkler.Explain("DIXON", "DICKSONX")
s.Matches        // 4
s.Transpositions // 0
s.Prefix         // 2
s.MatchedA       // [true true false true true]: the X of DIXON matched nothing
```

**Integers only.** Scores are parts per million, so no float reaches the chain.
Each score is computed from one exact rational with a single round-half-up at
the end: a Jaro-Winkler score is never the rounded Jaro score rounded a second
time. That is not cosmetic. The naive two-step port returns 961110 for
`MARTHA`/`MARHTA` where the published value is 0.9611111, and it is off by one
on five of this package's fourteen test vectors.

`Explain` is what `Jaro` and `Winkler` are both built on, and it returns the
whole working: the window, the match flags per rune, the transposition count
and the common prefix. A caller that wants to show *why* two strings scored
what they did reads those flags rather than recomputing them.

**Live demo:** [`r/moul/x/daily/jarowinklerdemo`](https://github.com/moul/gno-contracts/tree/main/r/moul/x/daily/jarowinklerdemo)
· render it at [`/r/moul/x/daily/jarowinklerdemo/v0`](https://gno.land/r/moul/x/daily/jarowinklerdemo/v0).
