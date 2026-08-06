# `gno.land/p/moul/x/daily/rot13/v1`

**ROT13 / Caesar letter-rotation cipher** — `Rot13`, `Caesar`.

Pure `strings.Map` logic over ASCII letters; everything else passes through
untouched. ROT13 shifts each letter 13 places and, since the alphabet has 26
letters, is its own inverse. `Caesar` generalizes it to any shift (negative and
large shifts normalized into `[0,26)`). Ports Go's classic ROT13 teaching
example.

```go
import "gno.land/p/moul/x/daily/rot13/v1"

s := rot13.Rot13("Hello, Gno!") // "Uryyb, Tab!"
d := rot13.Rot13(s)             // "Hello, Gno!" (own inverse)
c := rot13.Caesar("attack", 3)  // "dwwdfn"
```

**Live demo:** [`r/moul/x/daily/rot13demo`](https://github.com/moul/gno-contracts/tree/main/r/moul/x/daily/rot13demo/v1)
· render it at [`/r/moul/x/daily/rot13demo/v1`](https://gno.land/r/moul/x/daily/rot13demo/v1).
