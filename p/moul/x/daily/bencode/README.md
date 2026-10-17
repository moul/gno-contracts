# `gno.land/p/moul/x/daily/bencode/v0`

**Bencoding, the BitTorrent serialization format**: `Decode`, `Value.Encode`,
`NewInt`, `NewString`, `NewList`, `NewDict`.

```go
import "gno.land/p/moul/x/daily/bencode/v0"

v, err := bencode.Decode("d3:cow3:moo4:spam4:eggse")
v.Get("cow").Text()   // "moo"
v.Keys()              // ["cow", "spam"]
v.Encode()            // "d3:cow3:moo4:spam4:eggse", byte for byte

d := bencode.NewDict()
d.Set("spam", bencode.NewString("eggs"))
d.Set("cow", bencode.NewString("moo"))
d.Encode()            // "d3:cow3:moo4:spam4:eggse": insertion order does not matter
```

**Four types and no escape syntax.** Integers (`i42e`), byte strings
(`5:hello`), lists (`l...e`) and dictionaries (`d...e`). No float, no boolean,
no null. A string carries its length instead of quoting rules, so a value can
contain any byte, including the delimiters.

**The point is canonicality, and that is why the decoder is strict.** One value
has exactly one encoding: dictionary keys sorted bytewise, no leading zeros, no
negative zero, no trailing bytes. A BitTorrent infohash is the digest of a
re-encoded `info` dictionary, so a decoder that accepts a sloppy encoding and
re-emits a tidy one silently changes the identity of what it parsed. This one
**rejects** non-canonical input rather than normalizing it, which makes the
round trip a guarantee: for every input `Decode` accepts, `Encode` returns the
original bytes. `TestCanonicalIsAFixedPoint` pins that property.

`ErrNotCanonical` is kept apart from `ErrSyntax` on purpose: "this parses but no
encoder would emit it" is a different message to show a user than "this is not
bencode".

A nil never reaches the encoding: `Set` ignores a nil value and `NewList`
drops a nil item, because a nil would encode to nothing and emit a
dictionary or a list that this package's own `Decode` rejects.

Accessors never panic. `Int`, `Text`, `Len`, `At` and `Get` return the zero
value for the wrong kind or a nil receiver, so walking a document of unknown
shape cannot abort a realm call. Input is bounded by `MaxLen` (8192 bytes) and
`MaxDepth` (16) so gas stays predictable.

Not implemented: streaming, raw `[]byte` values distinct from strings, and
integers wider than `int64`.

**Live demo:** [`r/moul/x/daily/bencodedemo`](https://github.com/moul/gno-contracts/tree/main/r/moul/x/daily/bencodedemo)
· render it at [`/r/moul/x/daily/bencodedemo/v0`](https://gno.land/r/moul/x/daily/bencodedemo/v0).
