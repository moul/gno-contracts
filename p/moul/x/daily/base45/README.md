# `gno.land/p/moul/x/daily/base45/v0`

**RFC 9285 base45**: `Encode`, `EncodeBytes`, `Decode`, `DecodeBytes`,
`EncodedLen`, `Alphabet`.

```go
import "gno.land/p/moul/x/daily/base45/v0"

base45.Encode("AB")        // "BB8", not "8BB"
base45.Encode("ietf!")     // "QED8WEX0"
base45.Decode("%69 VD92EX0") // "Hello!!"
```

**It exists for QR codes, not for transport.** A QR symbol has an alphanumeric
mode whose character set is exactly these 45 characters, and it packs them at
5.5 bits each against the 8 that byte mode spends. Encoding a payload to base45
first costs 50% expansion (3 characters per 2 bytes) and still produces a
smaller symbol than handing the raw bytes to byte mode. That trade is why the
EU Digital COVID Certificate is base45, and it is the only reason to pick this
over base64.

**The ordering is the whole trap.** Two bytes are one 16-bit number written in
base 45, and the three characters are emitted **least significant first**. An
implementation that writes them the readable way round round-trips perfectly
against itself and fails against every other decoder in the world, which is why
the tests here are the RFC's published vectors and not generated pairs. A lone
trailing byte becomes two characters the same way, so an encoded length is
never `3n+1`.

Decoding is strict in both directions a string can be wrong. A character
outside the alphabet is rejected rather than skipped, and a group that decodes
above the range its byte count can hold is rejected rather than truncated:
`FGW` is `0xFFFF` and `GGW` is `0x10000`, one character apart. The alphabet is
uppercase, so `bb8` is corrupt input, not a case to fold.

`MaxLen` is 4096 on the input of every function, so gas stays predictable.

**Live demo:** [`r/moul/x/daily/base45demo`](https://github.com/moul/gno-contracts/tree/main/r/moul/x/daily/base45demo)
· render it at [`/r/moul/x/daily/base45demo/v0`](https://gno.land/r/moul/x/daily/base45demo/v0).
