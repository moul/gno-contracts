# `gno.land/p/moul/x/daily/ascii85/v0`

**Adobe/btoa ascii85 binary-to-text encoding** - `Encode`, `EncodeFramed`,
`Decode`, `ErrCorrupt`, `ErrOverflow`, `ErrTooLong`.

Four bytes become five printable characters from `!` to `u`.

```go
import "gno.land/p/moul/x/daily/ascii85/v0"

enc, _ := ascii85.Encode("Hello World!")       // 87cURD]i,"Ebo80
framed, _ := ascii85.EncodeFramed("Hello World!") // <~87cURD]i,"Ebo80~>
ascii85.Decode(framed)                         // "Hello World!", nil
```

**Why it exists: 25% expansion against base64's 33%.** Four hundred bytes
encode to 500 characters here, 536 in base64 and 800 in hex. You pay for it
with an alphabet that is neither URL-safe nor case-insensitive, which is why
base64 kept the web and ascii85 kept PostScript and PDF.

**It refuses the group Go silently wraps.** A five-character group is a base-85
numeral, and only values below 2^32 name four bytes, yet nothing in the
character set stops a stream from spelling a larger one. `encoding/ascii85` in
the Go standard library computes the group in a `uint32` and lets it wrap:
`s8W-"` is 2^32 exactly and decodes there to the same four zero bytes as the
one-character shortcut `z`, and `uuuuu` decodes to four bytes that appear
nowhere in the input (measured against Go 1.x, 2026-11-05). Two different texts
decoding to the same bytes is a forgery primitive wherever the text is what
gets signed, compared or used as a key, so `Decode` returns `ErrOverflow`
instead. It is the one deliberate incompatibility, and `s8W-!`, the group one
below the limit, still decodes, so the check is a boundary and not a blanket
refusal of large groups.

**The output is not a fixed ratio of the input.** Four zero bytes are written
as the single character `z`, but only on a group boundary: `abcd` + four
zeroes + `efgh` encodes to `@:E_WzAS,Rg`, while the same four zeroes one byte
earlier straddle two groups, neither of which is all zero, and cost five
characters instead of one. Decoding rejects a `z` that arrives once a group has
been started, for the same reason.

**Framing is optional and balanced.** `Decode` takes the bare stream or the
Adobe `<~`/`~>` form, and ignores whitespace between characters because the
encoding is written to be wrapped at a line width. A closing `~>` with no
opening `<~` is `ErrCorrupt` rather than a stream that happens to end in two
punctuation characters.

Edge cases: a final group of one character is rejected, since fewer than eight
bits cannot have come from a byte; a character outside `!` to `u` is rejected;
`MaxLen` bounds `Encode` at 4096 bytes and `MaxTextLen` bounds `Decode` at 5300
characters, so gas stays predictable; `EncodeFramed("")` is `<~~>`, which a
reader can tell from a missing stream.

Every expectation in the tests was produced by Go's `encoding/ascii85` and
copied, not computed by hand.

**Live demo:** [`r/moul/x/daily/ascii85demo`](https://github.com/moul/gno-contracts/tree/main/r/moul/x/daily/ascii85demo)
· render it at [`/r/moul/x/daily/ascii85demo/v0`](https://gno.land/r/moul/x/daily/ascii85demo/v0).
