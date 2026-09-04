# `gno.land/p/moul/x/daily/hexdump/v1`

**Classic `xxd -C` byte dump** — `Dump`, `DumpString`, `Line`, `Offset`, `Hex`,
`ASCII`, `Printable`, `MaxBytes`, `BytesPerLine`.

```go
import "gno.land/p/moul/x/daily/hexdump/v1"

out, n := hexdump.DumpString("café")
// 00000000  63 61 66 c3 a9                                    |caf..|
// n == 5 — "é" is two bytes
```

The familiar layout: 8-digit hex offset, 16 bytes as hex in two 8-byte groups,
then the ASCII view between pipes with non-printables as `.`. **Short final lines
are padded** so the ASCII gutter never shifts — that alignment is the whole point
of the format, and it has its own test asserting the gutter lands in the same
column on a full and a partial line.

Useful on chain for the same reason it is useful off it: when a value is not what
you expected, the bytes tell you why. Trailing whitespace, stray NULs, UTF-8 that
is not what it claims — all invisible in a rendered string and obvious in a dump.

`Dump` returns the number of bytes rendered alongside the text, so truncation at
`MaxBytes` (4096) is reported rather than silent.

**Live demo:** [`r/moul/x/daily/hexdumpdemo`](https://github.com/moul/gno-contracts/tree/main/r/moul/x/daily/hexdumpdemo/v1)
· render it at [`/r/moul/x/daily/hexdumpdemo/v1`](https://gno.land/r/moul/x/daily/hexdumpdemo/v1).
