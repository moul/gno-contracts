# `gno.land/r/moul/x/reaper/v0`

A noticeboard whose garbage is a standing bounty.

Anyone can post a note with an expiry. Posting locks a storage deposit, paid by
the poster. Once a note expires, **anyone at all** can delete it, and the chain
refunds that deposit to whoever signed the deleting transaction. The poster pays
to occupy space; a stranger is paid to reclaim it.

There is no token here, no reward pool and no emission schedule. The incentive
is the chain's own storage accounting, which already works this way for every
realm on gno.land. This realm only makes it legible.

## Why it is safe to let strangers delete things

`Reap` and `Compact` are permissionless because the expiry predicate is checked
on chain. A reaper cannot delete a note that has not expired, so the worst a
malicious caller can do is waste their own gas. That is the general pattern
worth taking away: where the predicate for "this is garbage" is cheap to verify
on chain, deletion needs no authorization at all, and the protocol is the
bounty.

The inverse is the warning. The chain pays for destruction, so in any realm
whose delete path is *not* predicate-guarded, authorization is the only thing
standing between it and profitable vandalism.

## The interface

| | |
|---|---|
| `Post(body, ttl)` | adds a note reapable `ttl` blocks from now, and locks its deposit against you. `ttl` 0 is allowed and is the cheapest demonstration |
| `Reap(limit)` | deletes up to `limit` expired notes. Permissionless. The refund goes to you. Unexpired notes are skipped, not refused, so a reaper never has to guess which indices are ripe |
| `Compact()` | frees the dead tree nodes reaping left behind. Permissionless, paid the same way |
| `Bounty()` | prices what is currently on the table, as a `storagecost.Quote` |
| `Reapable()` · `Compactable()` · `Live()` | free reads: the three numbers a bot needs |

## The ordering that turned out to matter

`Reap` walks from the **highest index down**, and that is economic rather than
cosmetic.

In the backing list the oldest indices are the *ancestors* of the newest, and a
node can only be freed once everything below it is dead. So a reap that took the
oldest notes first, which is the obvious way to drain an expiry queue, would
never create a dead tail: `Compactable` stays at zero and the tree structure
stays locked. That structure is not a rounding error. Measured on chain with 32
entries of 512 bytes, deleting the notes refunded 8,896 bytes and the subsequent
compaction refunded **a further 27,679**, because a list node costs more than the
note it carries.

Every candidate is expired either way, so the direction changes nothing about
what is legal to delete. It only changes how much the reaper gets paid, by about
4x. The measurement is in
[`p/moul/ulist`](https://github.com/moul/gno-contracts/tree/main/p/moul/ulist).

`Reap` and `Compact` stay separate calls because they are separate decisions,
and they are worth batching in that order: compaction returns nothing while a
live note still sits below the dead ones.

## A note body is attacker-controlled, and the board renders it

Anyone who pays the deposit chooses the bytes, and `Render` puts them on a page
every reader of the realm loads. That makes a note body untrusted input landing
in an **inline** markdown slot, the same category as a username or a post title,
and it is escaped with
[`p/nt/markdown/sanitize`](https://github.com/gnolang/gno/tree/master/examples/gno.land/p/nt/markdown/sanitize/v0)
`InlineText` before it reaches the page.

This realm shipped without that, and it is worth naming what the gap actually
allowed, because the hand-rolled version looked like it was doing the job:

```go
// what the board used to do, and what it stopped: only "\n" and "|"
oneLine := strings.ReplaceAll(strings.ReplaceAll(body, "\n", " "), "|", " ")
```

| a note containing | rendered as | so a poster could |
|---|---|---|
| `[Claim 100 GNOT](https://evil.example)` | a live link | phish every reader, with the realm's page as the attribution |
| `![x](https://evil.example/p.png)` | an image request | log the IP of everyone who opened the board |
| `<gno-columns>`, `<h5>` | gnoweb chrome | lay out the page, or forge a section heading |
| `\r`, U+2028, U+2029 | a line break | leave the bullet item and emit top-level markdown |
| U+202E, U+200B | nothing visible | reorder what a reader sees away from what the bytes say |

`InlineText` closes all five, and none of them were a bug in the incentive
design: the storage accounting was right, the rendering was not.

Two details that are easy to get backwards:

- **Truncate first, sanitize second.** The escaper works by inserting
  backslashes and is not idempotent, so cutting its output at an offset can
  strand a trailing lone backslash that escapes the chrome appended after it.
- **Cut on a rune boundary.** Slicing a body at byte 48 splits a multi-byte
  character in half and puts invalid UTF-8 on the page. One emoji in a note was
  enough.

The general rule, for any realm that renders something a caller stored: match
the helper to the slot the content lands in (inline text, block, table cell,
URL, code fence) and wrap each user-supplied string exactly once. The package
doc carries the table.

## What it is built from

The realm is thin on purpose. Two packages own the parts it does not:

- [`p/moul/ulist`](https://github.com/moul/gno-contracts/tree/main/p/moul/ulist)
  stores the notes and owns compaction. Its `Delete` is a soft delete that
  leaves a dead node behind, and its `Compact` frees those nodes without moving
  a live index.
- [`p/moul/x/storagecost`](https://github.com/moul/gno-contracts/tree/main/p/moul/x/storagecost)
  owns the arithmetic: what a byte refunds, and how many bytes a transaction
  must free to pay for itself.

## The figures on the page are estimates

No stdlib call exposes a realm's own locked storage, so every byte count in
`Render` is derived from payload length. Treat the bounty as an advertisement,
not a settlement. The authoritative numbers are the chain's, in the
`StorageDepositEvent` and `StorageUnlockEvent` each transaction emits.

<!-- BEGIN GNOCONTRACTS FOOTER (generated by `make readmes`; do not edit below) -->

---

Part of **[moul/gno-contracts](https://github.com/moul/gno-contracts)** — moul's versioned gno.land contracts. See the repository for the full catalog, build/test tooling, and usage.

**Dependency graph:**

![gno.land/r/moul/x/reaper/v0 dependency graph](https://raw.githubusercontent.com/moul/gno-contracts/main/_assets/gno.land/r/moul/x/reaper/v0/deps.png)

> 🧪 **Highly experimental — potentially vibe-coded.** Not audited; may break, change, or be removed at any time. Do not use with anything of value. Full disclaimer: [DISCLAIMER](https://github.com/moul/gno-contracts/blob/main/DISCLAIMER.md).

<!-- END GNOCONTRACTS FOOTER -->
