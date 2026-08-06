# `gno.land/r/moul/x/daily/markovdemo/v1`

Live demo of the [`p/moul/x/daily/markov`](https://github.com/moul/gno-contracts/tree/main/p/moul/x/daily/markov/v1)
Markov-chain text generator.

Holds one package-level `markov.Chain` as the on-chain corpus and wires it to the
chain — babbling is seeded by `runtime.ChainHeight()`, so `Generate` stays a pure,
reproducible query that still varies block to block. The realm ships pre-seeded
with a couple of sentences, so a fresh deploy already babbles:

- `Feed(cur, text)` — tokenize `text` and fold it into the corpus (the crossing
  function; any caller may enrich it).
- `Generate(nWords) string` — babble ~`nWords` words, seeded by the block height.
- `Stats() (int, int)` — returns `(totalWords, prefixCount)`.
- `Render("/60")` — a fresh 60-word sample plus corpus stats and a sample of
  prefix → suffix rows; `Render("")` defaults to 40 words.

All build/walk math lives in the library; this realm is just the wiring and the
gnoweb view. Render it at [`/r/moul/x/daily/markovdemo/v1`](https://gno.land/r/moul/x/daily/markovdemo/v1).
