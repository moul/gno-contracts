# `gno.land/p/moul/x/daily/hashring/v0`

**Consistent hashing with virtual nodes** (`New`, `Add`, `Remove`, `Get`, `GetN`, `Hash`).

A placement that survives a membership change. `hash(key) % n` is balanced and one
instruction, and it is wrong the moment `n` moves: going from four shards to five remaps
roughly 80% of the keys, because the modulus moved under every key at once. This maps keys
and nodes into the same 64-bit space, arranges that space in a circle, and gives a key to
the first node clockwise of it, so losing a node hands its arc to one neighbour and touches
nothing else.

```go
import "gno.land/p/moul/x/daily/hashring/v0"

r := hashring.New(hashring.DefaultReplicas)   // 64 points per node
r.Add("alpha")
r.Add("beta")
r.Add("gamma")

r.Get("session-91")          // "beta"
r.GetN("session-91", 3)      // ["beta" "gamma" "alpha"], the preference list

r.Remove("beta")             // only beta's keys move
r.Get("session-91")          // "gamma"

hashring.Hash("session-91")  // 0x… the position on the circle
```

**Measured, over 200 four-node memberships of 6,000 keys.** The gap between the largest and
smallest share, as a percentage of an even split:

| replicas | 1 | 8 | 16 | 32 | 64 | 128 |
|---|---|---|---|---|---|---|
| mean | 183% | 72% | 50% | 36% | 28% | 19% |
| worst | 355% | 158% | 110% | 77% | 64% | 41% |

That is the 1/sqrt(replicas) falloff: 64 times the points should cut the imbalance by 8 and
cut it by 6.5. `DefaultReplicas` is 64 because the curve is flat enough past it that the next
halving costs another 4x in points, and points are what every `Add` hashes and every `Get`
binary-searches.

**The hash is API, not an implementation detail.** SHA-256 truncated to its first eight
bytes, big-endian. Every placement a caller ever made is a function of it, so changing it is
not a refactor, it is a migration of everything that was ever stored by the result. That is
why `TestHashIsStable` pins three literal values and why no other test asserts a placement in
terms of a hash: the property tests compare one placement against another, so they would all
stay green through a hash swap that silently moved every key on chain.

**`GetN` clamps rather than pads.** Asking for more replicas than there are nodes is a
caller's miscount, and a list padded with repeats looks like it names `n` distinct homes
while naming fewer. It returns the membership instead.

**Colliding points are dropped, not stacked.** Two virtual points at one position leave the
later one owning an empty arc, so it buys nothing and costs a deeper binary search. The
alternative, ordering them by which node was added first, is a ring that two chains with the
same membership disagree about. At 64-bit hashes and a 131,072-point ceiling the odds of ever
seeing one are about 2^-31.

**It is a value, not realm state.** Nothing here imports the chain. A realm that wants a ring
across calls stores the membership, a handful of strings, and rebuilds: persisting a few
thousand sorted points to save a few hundred hashes is the wrong trade when storage is the
thing you are charged for. `MaxNodes` (256) and `MaxReplicas` (512) bound what a caller can
be handed either way.

**Live demo:** [`r/moul/x/daily/hashringdemo`](https://github.com/moul/gno-contracts/tree/main/r/moul/x/daily/hashringdemo)
· render it at [`/r/moul/x/daily/hashringdemo/v0`](https://gno.land/r/moul/x/daily/hashringdemo/v0).
