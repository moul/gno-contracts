# `gno.land/p/moul/x/daily/punycode/v0`

**RFC 3492 punycode, the bootstring encoding behind `xn--`**: `Encode`,
`Decode`, `EncodeDomain`, `DecodeDomain`.

```go
import "gno.land/p/moul/x/daily/punycode/v0"

punycode.Encode("bücher")                  // "bcher-kva"
punycode.Decode("wgv71a119e")              // "日本語"
punycode.EncodeDomain("bücher.example")    // "xn--bcher-kva.example"
punycode.DecodeDomain("xn--mnchen-3ya.de") // "münchen.de"
```

A realm that stores a name typed by a human, and a wire format that only
accepts a narrow ASCII subset, are the two ends this sits between. It is how an
address bar shows `münchen.de` while DNS carries `xn--mnchen-3ya.de`.

**Punycode is not a cipher over bytes, and that is the whole design.** Every
basic (ASCII) character is copied out first, verbatim, and only the *positions*
of the non-basic ones are compressed afterwards. So `Hello-münchen-2024` stays
legible in its encoded form, and an all-ASCII string encodes to itself.

Four behaviours worth knowing before you use it:

- **An all-ASCII label still gets a trailing `-`.** `Encode("abc")` is `"abc-"`,
  not `"abc"`: the delimiter is what tells the decoder where the verbatim part
  ends. Without it `"abc"` would be read as three deltas.
- **The *last* delimiter splits the input, not the first.** That is what lets a
  literal part contain hyphens, so `"-> $1.00 <-"` survives the round trip (RFC
  3492 section 7.1 vector S).
- **`EncodeDomain` only prefixes a label that needed encoding**, so it is
  idempotent: run it twice and the second pass sees only ASCII and changes
  nothing.
- **Uppercase bootstring digits are rejected, not folded.** This encoder never
  emits them, and accepting them would let two spellings decode to one label.

**Decoding is total and bounded, deliberately.** Every ASCII input returns a
value or an error: a non-ASCII byte, a character outside the alphabet, a number
truncated mid-sequence, and a delta describing a code point past `U+10FFFF` are
all errors. A `Render` that panics on a user-supplied label is a permanently
unreadable page, and a decoder that loops on one is worse.

**What this is not: nameprep or IDNA2008.** No case folding, no normalization,
no confusable or bidi checks. It encodes exactly what it is given, so it is a
codec and never an answer to whether two domain names are the same.

Input is capped at `MaxLen` (1024 bytes). A DNS label is 63 bytes and a full
name 253, so the cap is generous for the real use and still a hard stop on gas.

**Live demo:** [`r/moul/x/daily/punycodedemo`](https://github.com/moul/gno-contracts/tree/main/r/moul/x/daily/punycodedemo)
· render it at [`/r/moul/x/daily/punycodedemo/v0`](https://gno.land/r/moul/x/daily/punycodedemo/v0).
