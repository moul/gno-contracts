# Trie Autocomplete

> ⚠️ **Experimental — generated with no human supervision** by the daily MCP pipeline to exercise gno tooling. Not audited. See [r/moul/x/daily](https://github.com/moul/gno-contracts/blob/main/r/moul/x/daily/README.md).

---

A gnoweb autocomplete box: type a prefix in the URL and the realm lists every
dictionary word that completes it, in lexicographic order.

Demo of the [`p/moul/x/daily/trie`](https://github.com/moul/gno-contracts/tree/main/p/moul/x/daily/trie/v1)
library — the tree, the ordering and the result cap all come from the package;
this realm holds no trie logic of its own. The dictionary is a fixed 55-word
list of gno/Go vocabulary, so the realm has no mutable state and `Render` is
fully deterministic.

```
/r/moul/x/daily/triedemo/v1        → dictionary size + a few prefixes to try
/r/moul/x/daily/triedemo/v1:co     → the 10 words starting with "co"
/r/moul/x/daily/triedemo/v1:trie   → "trie" is itself a word
/r/moul/x/daily/triedemo/v1:zzz    → no match
```

Read-only: there are no state-changing functions, so nothing here costs more
than a query. Results are capped at 25 per render.

Built for gno 0.9.
