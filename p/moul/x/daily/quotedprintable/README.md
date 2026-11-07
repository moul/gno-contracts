# `gno.land/p/moul/x/daily/quotedprintable/v0`

**Quoted-printable, both rulesets**: `Encode`, `Decode`, `EncodeWord`,
`DecodeWord`.

```go
import "gno.land/p/moul/x/daily/quotedprintable/v0"

quotedprintable.Encode("café au lait")      // "caf=C3=A9 au lait"
quotedprintable.EncodeWord("café au lait")  // "=?UTF-8?Q?caf=C3=A9_au_lait?="
quotedprintable.Decode("caf=e9")                 // "caf\xe9", lowercase hex accepted
```

**Two rulesets, and they disagree on purpose.** RFC 2045 section 6.7 is the
**body** encoding: printable ASCII stays literal, everything else becomes `=XX`,
and lines wrap at 76 columns with a `=\r\n` soft break. RFC 2047 section 4.2 is
the **header word**: the same escape, but a space becomes `_`, `?` and `_` stop
being safe, and the result is wrapped in `=?UTF-8?Q?...?=`.

Reusing one for the other is the classic quoted-printable bug. `why not?` is
left completely alone by the body encoder and becomes `=?UTF-8?Q?why_not=3F?=`
as a header word: run a subject line through the body codec and it looks
encoded, while the receiving parser stops at the first `?`.

Three behaviours worth knowing before you use it:

- **The body encoder is a binary encoder, deliberately.** CR and LF are data,
  written as `=0D` and `=0A`, never emitted as line structure. A realm encodes
  a payload, not an RFC 822 message, and an encoder that normalised line
  endings on the way through would quietly break a signature. The consequence
  is the property worth having: `Decode(Encode(s)) == s` for every `s`.
- **A literal space or tab never lands in the last four columns of a line.**
  Every transport is allowed to strip trailing whitespace, so one that gets
  that close to the wrap is encoded as `=20` or `=09` instead. This is stricter
  than Go: `mime/quotedprintable` emits `...aaaa =\r\n`, a literal space one
  character before the soft break, which is legal because the `=` and not the
  space is what ends the line. Both decode to the same bytes; the invariant
  here is the one that needs no exception to state.
- **`EncodeWord` always produces a word**, even for pure ASCII that needs no
  escaping, where Go's `mime.QEncoding` returns the input unchanged. A caller
  that encodes conditionally has to answer "is this already an encoded word"
  somewhere else; this one does not. It refuses past 75 characters with
  `ErrWordTooLong` rather than emitting a header no parser is required to
  accept, because splitting a long header across several words is a caller
  decision and not a silent one.

Decoding is strict where a wrong answer could pass unnoticed: an `=` that is
neither a soft break nor a valid hex pair is `ErrCorrupt`, never a literal `=`.
It is lenient where the intent is unambiguous: lowercase hex, a bare `\n` as a
soft break, and a byte that should have been encoded is passed through.
Whitespace at the end of a line is dropped, because RFC 2045 says it cannot
have been part of the data.

**What it does not do.** No transcoding: `DecodeWord` reads the charset label
and ignores it, so anything other than UTF-8 or US-ASCII comes back as the
bytes that were sent. No `B` (base64) encoded-words, which return
`ErrUnsupportedEncoding`. And `EncodeWord` leaves RFC 2047's *especials*
(`()<>@,;:\"/[]?.=` minus the three it already escapes) literal, which is
correct for an unstructured field such as `Subject` and not sufficient for a
display name inside a structured one.

Input is capped at `MaxLen` (4096 bytes; four times that for `Decode`) so gas
stays predictable.

**Live demo:** [`r/moul/x/daily/quotedprintabledemo`](https://github.com/moul/gno-contracts/tree/main/r/moul/x/daily/quotedprintabledemo)
· render it at [`/r/moul/x/daily/quotedprintabledemo/v0`](https://gno.land/r/moul/x/daily/quotedprintabledemo/v0).
