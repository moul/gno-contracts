# `gno.land/p/moul/x/daily/hmac/v0`

**Keyed-hash message authentication** (`Sum`, `SumSHA256`, `HexSHA256`, `VerifySHA256`,
`Equal`, `Truncate`, `SHA256`).

A hash answers "has this message changed". A MAC answers "did the holder of this key produce
this message", which is the question almost every protocol is actually asking. HMAC, as
specified by RFC 2104 and FIPS 198-1, is how you get the second answer out of a hash that
only offers the first.

```go
import "gno.land/p/moul/x/daily/hmac/v0"

tag := hmac.SumSHA256([]byte("key"), []byte("message"))   // 32 bytes
hmac.VerifySHA256([]byte("key"), []byte("message"), tag)  // true

hmac.HexSHA256("Jefe", "what do ya want for nothing?")
// "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"

hmac.Truncate(tag, 16)   // HMAC-SHA-256-128, RFC 2104 section 5
hmac.Equal(tag, other)   // no early exit on the first differing byte
```

**The construction, and why it is two hashes and not one.**

```
tag = H((K' xor 0x5c…) || H((K' xor 0x36…) || message))
```

`sha256(key || message)` is the MAC everybody writes first. It is 32 bytes, it changes with
both inputs, and it is forgeable: a Merkle-Damgard hash publishes its internal state as its
output, so anyone holding one valid tag can append to the message and compute a valid tag for
the longer one without ever seeing the key. HMAC runs the hash twice under two derivations of
the key, and the inner digest an attacker would need to extend never leaves the function.
`TestNotAPrefixMAC` is the assertion that refuses the shortcut.

**Conformance is the test, not a claim.** The suite runs six of RFC 4231's seven HMAC-SHA-256
vectors as published constants, plus the empty-key empty-message case. Case 4's key is a hex
literal rather than a run of one byte and is kept separate, because a fixture built by the
same helper as the code it tests can be wrong in the same direction.

**Two distinct keys can give one tag, twice over, and both are properties rather than bugs:**

| key | becomes | so |
|---|---|---|
| longer than 64 bytes | its own SHA-256 | a 131-byte key and its 32-byte digest are one key |
| shorter than 64 bytes | zero-padded to 64 | `k` and `k` followed by zeros are one key |

Both are pinned by tests and both are the RFC's behaviour. Keys of exactly 32 random bytes
sit in neither class.

**`Equal` buys an answer, not constant time.** It compares lengths first, then reads every
byte of both. The point is that a verifier returning on the first differing byte tells the
caller how many leading bytes of a guessed tag were right, which turns forging from 2^256
work into 32 rounds of 256 guesses. Wall-clock timing is not something a contract can observe
or promise, so the doc comment claims the operation count and nothing more.

**The hash is a parameter.** `Sum` takes a `HashFunc`, a one-shot `func([]byte) []byte`, and
the hash's internal block size. 64 for SHA-256, which is not its 32-byte digest size: using
the digest size there produces tags that look fine and match nothing. `SumSHA256` is the thin
wrapper and a test pins that it is nothing more.

> ⚠️ **A realm cannot keep a secret.** Everything in realm state is readable by anyone, so a
> long-lived key stored on chain authenticates nobody. The shapes that work are verifying
> against a key the caller supplies in the transaction, or a commitment published now and
> opened later.

**Live demo:** [`r/moul/x/daily/hmacdemo`](https://github.com/moul/gno-contracts/tree/main/r/moul/x/daily/hmacdemo)
· render it at [`/r/moul/x/daily/hmacdemo/v0`](https://gno.land/r/moul/x/daily/hmacdemo/v0).
