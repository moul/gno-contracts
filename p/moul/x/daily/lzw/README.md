# `gno.land/p/moul/x/daily/lzw/v0`

**Lempel-Ziv-Welch, with a decoder that validates**: `Encode`, `Encoded.Decode`,
`Encoded.Steps`, `Encoded.Codes`, `Encoded.Saved`.

```go
import "gno.land/p/moul/x/daily/lzw/v0"

enc, _ := lzw.Encode("mississippi")  // 81 bits against 88 raw
enc.Codes()                          // 109 105 115 115 257 259 112 112 105
enc.Decode()                         // "mississippi", or ErrCorrupt
```

LZW learns as it reads. Both sides start from the same 256 entries, one per
byte, and both add the same new entry after every code, so **the dictionary is
never transmitted**. That is the whole difference from Huffman, where the table
*is* the header: here the payload is nothing but a stream of codes, and the
table is a consequence of the codes rather than a thing beside them. The trade
goes the other way too. Huffman pays for a table up front and then wins on
skew; LZW pays nothing up front and wins only on repetition, so a short
unrepeating input comes out **larger**, by the ratio of a nine-bit code to an
eight-bit byte. `Saved` returns a negative number there, which is the honest
answer and not a bug.

**The decoder is one entry behind the encoder, always.** The encoder emits the
code for the longest match it holds, then adds that match plus the next byte;
the decoder cannot add anything until it has read the code *after* the one it
is decoding, because the entry it must add ends in a byte it has not seen yet.
Two things follow, and both are where a naive implementation breaks:

- **A code can arrive before its entry exists**, exactly one past the end of
  the table. It happens on any run of a repeating pattern, and `"aaaaa"` is the
  shortest input that does it: the encoder emits the code for `"aa"` on the
  very step that creates it. The entry can only be the previous one with its
  own first byte appended, and `Decode` synthesises it. A decoder that just
  looks codes up returns an error on five bytes of `a`.
- **The code width has to grow on the same code for both sides**, even though
  their tables disagree about how full they are. Codes start at 9 bits and
  widen as the dictionary fills; the encoder widens after adding the entry that
  filled the old width, and the decoder has added one fewer by then, so it
  widens **one entry early**. Get that wrong and every later code is read
  shifted by a bit, which does not fail: it returns a different string. The
  boundaries are code 257 (10 bits), 769 (11) and 1793 (12).

**There is no CLEAR code.** The dictionary freezes at `MaxWidth` bits, 4096
entries, and stays frozen. That costs a little compression on a long input
whose statistics change halfway through, and buys a stream with exactly one
interpretation: a reset code is a second thing the two sides have to agree
about, and agreeing about one is already the hard part.

**The decoder validates, deliberately.** `Encoded` is a plain struct with
exported fields, so a caller can build one by hand or read one back out of
storage, and a decoder that trusts what it is handed returns a string nobody
ever encoded. `Decode` refuses a first code that is not a single byte (the
table holds nothing else at that point), a code past the end of its own table,
a stream that ends mid-code, nonzero padding in the last byte, a `Data` slice
that is not exactly the bytes `NBits` needs, output that grows past `Size`, and
a result whose length is not `Size`. A spare byte and dirty padding are not
cosmetic: both are a way to carry a second payload that decodes to the same
string.

`Steps` returns the stream decoded code by code, each with the string it
expanded to **and the width it occupied**. The width belongs to the position in
the stream, not to the code sitting in it, which is why a caller showing the
stream to a human should not try to recompute it.

`MaxLen` is 4096 bytes. Symbols are bytes, not runes: a multi-byte UTF-8
character is several symbols, and round-tripping is byte-exact either way.

Live demo: [`r/moul/x/daily/lzwdemo`](https://github.com/moul/gno-contracts/tree/main/r/moul/x/daily/lzwdemo).

Built for gno 0.9.
