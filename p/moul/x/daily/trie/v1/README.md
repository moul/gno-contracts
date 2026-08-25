# `gno.land/p/moul/x/daily/trie/v1`

**Prefix tree (trie) for autocomplete** — `Insert`, `Contains`, `HasPrefix`, `Complete`, `Words`, `FromWords`, `MaxWordLen`.

Insert words, then ask for everything sharing a prefix. Children are stored in a
slice kept sorted by rune (binary search on lookup, insertion sort on add), so
completions always come back in lexicographic order and the output never depends
on insertion order — no maps anywhere, because Go/gno map iteration order is
unspecified and would make a realm's `Render` vary between calls. No clocks and
no chain imports either: same input, same output, always.

`MaxWordLen` (64) bounds a single word so insertion gas stays predictable.

```go
import "gno.land/p/moul/x/daily/trie/v1"

t := trie.FromWords([]string{"carpet", "car", "cat"})
t.Complete("car", 0)   // ["car" "carpet"] — lexicographic, 0 = no cap
t.Complete("car", 1)   // ["car"]
t.Contains("car")      // true
t.Contains("ca")       // false — a prefix is not a word until inserted
t.HasPrefix("ca")      // true
t.Words()              // ["car" "carpet" "cat"]
```

`Complete` returns an empty (never nil) slice for an unknown prefix, so callers
can range over the result without a nil check. The empty prefix lists the whole
trie, which makes it usable as a plain sorted listing too.

**Live demo:** [`r/moul/x/daily/triedemo`](https://github.com/moul/gno-contracts/tree/main/r/moul/x/daily/triedemo/v1)
· render it at [`/r/moul/x/daily/triedemo/v1`](https://gno.land/r/moul/x/daily/triedemo/v1).
