# `gno.land/p/moul/x/daily/cobs/v0`

**Consistent Overhead Byte Stuffing: removes every zero byte from a payload so a zero can delimit records, at one byte per 254 and never more**: `Encode`, `Decode`, `Frame`, `Pack`, `Unpack`, `MaxEncodedLen`.

```go
import "gno.land/p/moul/x/daily/cobs/v0"

cobs.Encode("\x11\x22\x00\x33")          // → "\x03\x11\x22\x02\x33", one byte added
cobs.Encode("\x00\x00\x00")              // → "\x01\x01\x01\x01", still one byte added
cobs.Pack([]string{"a\x00b", "", "c"})   // → one string, three records, zeros as separators
cobs.Unpack(packed)                      // → []string{"a\x00b", "", "c"}, nil
cobs.MaxEncodedLen(1000)                 // → 1004, the worst case, without encoding
```

A realm that concatenates arbitrary byte records into one stored string has to take them
apart again later, and the two usual answers are both bad on chain. A length prefix makes the
stream unreadable from anywhere but the start, so finding the fourth record means parsing the
first three. Escaping the separator makes the worst case twice the gas of the average one,
and the worst case is a payload of zeros, which is exactly what a zero-padded or
freshly-allocated record looks like.

COBS drops the zeros instead of escaping them and writes the distances between them. The
output is a run of groups, each a code byte followed by up to 254 non-zero payload bytes,
where the code is the group length plus one and an implied zero sits at the end of any group
that did not fill. Nothing in the output can be a zero, so a zero is free to mean "record
ends here", and the cost is one code byte per 254 bytes of payload whatever the payload is.

**The payload an escaper fears is the cheap one here.** All zeros costs exactly one byte, at
any length, because every group closes before it can fill. The expensive direction is the
opposite one: a payload with no zeros at all pays one code byte per 254 bytes. Measured by
`TestOverheadStaysBounded`, at 1000 bytes that is +1 against +4, where escaping would be
+1000.

**Only the canonical frame decodes, deliberately.** A full group is closed when the next byte
arrives and not when it fills, so a payload of exactly 254 non-zero bytes is 255 bytes and not
256. An encoder that closes eagerly appends a trailing `01` group carrying neither a payload
byte nor an implied zero: the same payload, two frames, two hashes for one piece of state.
`Decode` returns `ErrNotCanonical` for that shape rather than accepting both, so a realm
storing or comparing frames finds out at the boundary instead of at the comparison. It is also
the single most common way an implementation ends up disagreeing with every other one on the
wire, which is why all ten rows of Table 1 of Cheshire and Baker are pinned as test vectors.

Four behaviours worth knowing before you use it:

- **`Encode` never returns an empty string and never returns a zero byte.** The empty payload
  encodes to `01`, one code byte, so a frame of nothing is still distinguishable from no frame.
  `Decode("")` is `ErrEmptyFrame` for the same reason.
- **`Pack` and `Unpack` are the pair most callers want.** `Pack` frames each record and closes
  it with a zero, `Unpack` splits on zeros and decodes each. `Unpack` refuses a stream whose
  last frame has no delimiter with `ErrTruncated`: a stream still being written would otherwise
  hand back a partial record that looks exactly like a complete one.
- **Encoding appends to a byte slice, decoding reads a string.** `AppendEncode(dst []byte, src
  string) []byte` is Go's `encoding` shape, and it is a slice because a string accumulator
  copies the whole prefix on every append, which makes packing a sequence quadratic in the
  encoded size. Decoding takes a string because that is what a realm has stored.
- **The errors are distinct for a reason.** `ErrDelimiter` means a zero appeared where the
  encoding can never put one, so the frame was cut at the wrong place. `ErrTruncated` means
  more input would have helped. `ErrNotCanonical` means the bytes decode fine but should never
  have been written. A caller validating untrusted input wants to tell the third from the
  first two.

Encoding and decoding are both one pass, O(bytes), with no table and no allocation per group.
`MaxEncodedLen` answers the sizing question without encoding, and it is an upper bound rather
than the exact length, which depends on where the zeros are. There is no streaming reader: the
unit is a frame, and a realm holding many of them calls `AppendEncode` into one buffer in a
loop, which is what `Pack` does.

Live demo: [r/moul/x/daily/cobsdemo](/r/moul/x/daily/cobsdemo/v0).
