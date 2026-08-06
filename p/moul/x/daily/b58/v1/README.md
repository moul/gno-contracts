# `gno.land/p/moul/x/daily/b58/v1`

**Base58 (Bitcoin alphabet) codec** — `Encode`, `Decode`, `IsValid`, `Alphabet`.

Pure byte-slice math (the classic div/mod-by-58 carry loop), no `math/big`;
leading zero bytes ↔ leading `1`s. Ported from `mr-tron/base58` / `btcutil/base58`.

```go
import "gno.land/p/moul/x/daily/b58/v1"

s := b58.Encode([]byte("hello"))  // "Cn8eVZg"
b := b58.Decode(s)                // []byte("hello") (nil if s has a non-alphabet char)
```

**Live demo:** [`r/moul/x/daily/b58demo`](https://github.com/moul/gno-contracts/tree/main/r/moul/x/daily/b58demo/v1)
· render it at [`/r/moul/x/daily/b58demo/v1`](https://gno.land/r/moul/x/daily/b58demo/v1).
