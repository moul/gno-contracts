# `gno.land/p/moul/x/daily/murmur3/v0`

**MurmurHash3 x86_32** - `Sum32`, `Sum32Seed`, `SumHex`, `Hex`, `Bucket`,
`Verification`.

Austin Appleby's non-cryptographic hash. Reads four bytes at a time, scrambles
each block with two odd constants and a rotate, folds the length in, and
finishes with an avalanche of shift-xor-multiply that spreads every input bit
over every output bit.

```go
import "gno.land/p/moul/x/daily/murmur3/v0"

murmur3.SumHex("abc")            // "b3dd93fa"
murmur3.Sum32("")                // 0
murmur3.Sum32Seed("abc", 1)      // 0xaa75e9ff, unrelated to the seed-0 result
murmur3.Bucket("moul", 16)       // 3, a deterministic shard
murmur3.Verification()           // 0xb0f57ee3, the SMHasher self-test
```

**What it is for:** bucketing. Spreading keys over a fixed number of shards,
sizing a sketch, picking a deterministic slot, keying one of the independent
hash functions a Bloom filter or a count-min sketch needs (that is what the
seed is for: it re-keys the whole function).

`Bucket` spreads evenly up to `MaxBuckets`, which is `1 << 32`, and the ceiling
is the hash rather than the arithmetic: 32 bits of output name 2^32 slots and
no more. A larger `n` is accepted and answered in range, but every index from
2^32 up is unreachable, so the top half of a 2^33-way split would never see a
key. Nothing rejects it, because that `n` is a caller bug and a panic inside a
`Render` is a worse way to find out than a skewed table.

`Verification` is the reason this package can claim to be the same function as
everyone else's. It runs SMHasher's procedure, hashing 256 keys of growing
length under 256 seeds and hashing the results, and a correct MurmurHash3
x86_32 answers `0xb0f57ee3`. One wrong constant, one mis-ordered tail byte or a
rotate in the wrong direction moves it, and no amount of reading the code finds
that. The test asserts it, and the demo realm recomputes it on chain.

> ⚠️ **Not a cryptographic hash.** MurmurHash3 is trivially invertible and
> collisions are cheap to generate, so anyone who chooses the input chooses the
> bucket. It is not a commitment, not a signature, and a table keyed by
> caller-supplied strings can be driven into its worst case on purpose.

**Live demo:** [`r/moul/x/daily/murmur3demo`](https://github.com/moul/gno-contracts/tree/main/r/moul/x/daily/murmur3demo)
· render it at [`/r/moul/x/daily/murmur3demo/v0`](https://gno.land/r/moul/x/daily/murmur3demo/v0).
