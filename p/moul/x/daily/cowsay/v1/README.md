# `gno.land/p/moul/x/daily/cowsay/v1`

**cowsay** — `Say(msg string) string` returns the classic ASCII cow with a
speech bubble containing `msg`.

Pure deterministic string art: the message is word-wrapped into a speech balloon
(single line uses `< >`, multi-line uses `/ \ | |` borders) with the happy cow
stacked underneath. Port of cowsay by Tony Monroe (1999); no `os`/`exec`, no
chain coupling.

```go
import "gno.land/p/moul/x/daily/cowsay/v1"

art := cowsay.Say("Hello, gno.land!")  // bubble + cow, ready for a code block
cowsay.Say("")                          // default message ("Moo!")
```

**Live demo:** [`r/moul/x/daily/cowsaydemo`](https://github.com/moul/gno-contracts/tree/main/r/moul/x/daily/cowsaydemo/v1)
· render it at [`/r/moul/x/daily/cowsaydemo/v1`](https://gno.land/r/moul/x/daily/cowsaydemo/v1).
