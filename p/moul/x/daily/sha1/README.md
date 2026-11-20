# `gno.land/p/moul/x/daily/sha1/v0`

**SHA-1 (FIPS 180-1, RFC 3174)** `Sum`, `SumHex`, `Hex`, `Verify`, `New`,
`Digest.Write`, `Digest.Sum`, `Digest.Reset`, `HMAC`, `HMACHex`, `GitBlobID`.

Forty hex digits from any amount of input. The message is compressed 64 bytes
at a time into five 32-bit words through 80 rounds, and the whole algorithm is
those rounds plus one padding rule: a `0x80` byte, zeros up to 56 bytes mod 64,
then the length in bits as a big-endian `uint64`.

```go
import "gno.land/p/moul/x/daily/sha1/v0"

sha1.SumHex("abc")                    // "a9993e364706816aba3e25717850c26c9cd0d89d"
sha1.GitBlobID("hello world\n")       // "3b18e512dba79e4c8300dd08aeb37f8e728b8dad"
sha1.HMACHex("Jefe", "what do ya want for nothing?")
```

`Digest.Sum` is **not destructive**: it pads a copy, so a digest can be read,
written to again, and read again. That is the only reason the streaming form is
worth having, and there is a test asserting chunked equals one-shot.

`GitBlobID` hashes `blob <len>\x00<content>`, which is what `git hash-object`
does. The header is the entire difference between a git id and a content hash,
and the empty file's `e69de29b...` is the one digest a git user recognises.

Almost every bug in a hand-written SHA-1 lives in the padding rule, so the
tests walk lengths 54, 55, 56, 57, 63, 64, 65, 119 and 128 across the boundary
rather than hashing one long string and hoping.

> ⚠️ **SHA-1 is broken as a collision-resistant hash.** SHAttered (2017)
> produced two different PDFs with the same digest and a chosen-prefix
> collision followed in 2020. Never use it to decide that two documents are the
> same document, and never build a new signature scheme on it. It is still the
> correct answer where an external format specifies it: git object ids,
> HMAC-SHA1 in TOTP and older AWS signatures, legacy checksum interop.

**Live demo:** [`r/moul/x/daily/sha1demo`](https://github.com/moul/gno-contracts/tree/main/r/moul/x/daily/sha1demo)
· render it at [`/r/moul/x/daily/sha1demo/v0`](https://gno.land/r/moul/x/daily/sha1demo/v0).
