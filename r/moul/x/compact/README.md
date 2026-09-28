# `gno.land/r/moul/x/compact/v0`

Fragmentation, as a number you can act on.

A soft delete frees nothing. It clears the element and leaves the tree node
behind, so the bytes stay locked and every read still walks past the hole.
Compacting drops those nodes, and the chain refunds their deposit **to whoever
signs the transaction**. Compaction is therefore paid work, and the only real
question is *when*: too early and you free too few nodes to cover the gas, too
late and every read has been paying for the holes in between.

This realm refuses to answer that question. It publishes the integers the
answer is made of and lets whoever is watching decide, because the realm cannot
see the gas price of the day and the caller can.

## The interface

| | |
|---|---|
| `Add(text)` | appends an entry and locks its deposit against you |
| `Drop(index)` | soft-deletes **your own** entry, which is what creates a hole. Frees nothing |
| `Compact()` | drops the dead nodes. Permissionless, and the refund goes to you |
| `Fragmentation()` | live against allocated, the free read a bot polls |
| `Reclaimable()` | what a `Compact` would actually free right now |
| `Quote()` | that, priced, as a `storagecost.Quote` |

Only the author may `Drop`, so the fragmentation here is the honest kind that
ordinary use produces rather than vandalism. `Compact` stays open to anyone,
and that asymmetry is the mechanism: **choosing what dies is owned, reclaiming
it is not.**

## Why `allocated - live` is the wrong number

The obvious reading of fragmentation is the gap between allocated indices and
live elements. It is not what a compaction frees.

A dead element only becomes a reclaimable node once **everything under it is
also dead**. So a board with many scattered holes reports a large gap and
reclaims almost nothing, while a board with a dead tail reclaims a lot from the
same gap. `Reclaimable()` is the real number and it is free to read.

That is the whole reason this cannot be a schedule or a heuristic baked into
the package. The shape of the holes decides, the shape changes with use, and
only a caller watching both integers can time it.

## Why this quote is sounder than a reaper's

A reaper advertises what deleting entries will refund, and to do that it has to
guess how much state an entry occupies from its payload length. That guess is
bad at the small end, where a per-entry floor dominates the payload, and one
realm under-advertised by **25x** on chain because of it.

Compaction has no such problem:

| | reaper's bounty | this quote |
|---|---|---|
| quantity | payload bytes, **guessed** from string length | dead nodes, **counted** by the container |
| conversion | a ratio measured at one payload size | a per-node constant, measured twice at 856 bytes |
| fails when | entries are small, or the container dominates | never structurally; the constant can drift |

`Quote()` is a measured constant times an exact integer. Still an estimate, and
the chain's `StorageUnlockEvent` is still the only settlement, but the failure
mode that cost a reaper 25x is absent by construction.

`TestQuoteCountsNodesRatherThanGuessingFromPayload` pins it: eight entries of 1
byte and eight of 256 produce the identical quote, because the node is what
gets freed.

## What it is built from

- [`p/moul/ulist`](https://github.com/moul/gno-contracts/tree/main/p/moul/ulist)
  stores the entries and owns compaction. Its `Compact` drops dead nodes
  without moving a live index, so an index is stable for the life of the realm.
- [`p/moul/x/storagecost`](https://github.com/moul/gno-contracts/tree/main/p/moul/x/storagecost)
  owns the arithmetic, including `EstimateNodes` and the measured
  `BytesPerTreeNode`.
- [`p/moul/kit/ui`](https://github.com/moul/gno-contracts/tree/main/p/moul/kit/ui)
  owns the display, including escaping an entry before it reaches the page.

## Related

[`r/moul/x/reaper`](https://github.com/moul/gno-contracts/tree/main/r/moul/x/reaper)
is the other half: it deletes expired entries, where this one reclaims what
deletion left behind. Reap first, then compact, because compaction returns
nothing while a live element still sits below the dead ones.
