# `gno.land/r/moul/x/pairs/aaabbb/v0`

One AMM pair, AAA/BBB, and nothing else: the worked example of an instance realm.

Read the file, it is the point. Two constants, an `init` that builds the pair and
registers it, and one-line re-exports forwarding `cur` into
[`p/moul/x/pair/v0`](../../../../../p/moul/x/pair/v0). It is `tools/pairgen.py`
output, differing only in its doc comment and in two blank imports that force the
in-repo test tokens to initialise first (an instance deployed against
already-deployed tokens needs neither).

```sh
python3 tools/pairgen.py gno.land/r/moul/x/pairs/aaa/v0.AAA \
    gno.land/r/moul/x/pairs/bbb/v0.BBB -o /tmp/out --namespace moul/x/pairs
diff /tmp/out/aaabbb/v0/aaabbb.gno r/moul/x/pairs/aaabbb/v0/aaabbb.gno
```

Trades against the two throwaway faucet tokens `r/moul/x/pairs/aaa/v0` and
`r/moul/x/pairs/bbb/v0`. Neither has any value.
