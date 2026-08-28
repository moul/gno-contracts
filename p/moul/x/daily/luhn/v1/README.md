# `gno.land/p/moul/x/daily/luhn/v1`

**Luhn mod-10 checksum** — `Valid`, `CheckDigit`, `Append`, `MaxLen`.

The check behind credit-card numbers, IMEIs and many national ID schemes
(Hans Peter Luhn, 1954). Spaces and hyphens are ignored, so the formatting a
human would paste works as-is.

```go
import "gno.land/p/moul/x/daily/luhn/v1"

luhn.Valid("4539 1488 0343 6467")   // true  — separators ignored
luhn.Valid("4539148803436468")      // false — one digit off
luhn.CheckDigit("7992739871")       // 3, true
luhn.Append("7992739871")           // "79927398713", true
```

> ⚠️ **A typo check, not a security check.** Luhn catches every single-digit
> error and nearly every transposition of adjacent digits, but anyone can
> compute a valid number in a second, and validity says nothing about whether
> the identifier exists. Never use it to authorize anything on-chain.

`MaxLen` (64) bounds an input so validation gas stays predictable. Note that a
string of zeros is technically Luhn-valid and is accepted — reject it in the
caller if your domain needs to.

**Live demo:** [`r/moul/x/daily/luhndemo`](https://github.com/moul/gno-contracts/tree/main/r/moul/x/daily/luhndemo/v1)
· render it at [`/r/moul/x/daily/luhndemo/v1`](https://gno.land/r/moul/x/daily/luhndemo/v1).
