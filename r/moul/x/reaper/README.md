# `gno.land/r/moul/x/reaper/v1`

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

## Reading it from outside: every number is a query

`v0` is live at [`gno.land/r/moul/x/reaper/v0`](https://gno.land/r/moul/x/reaper/v0); `v1`
is this source, and is not published yet. A package path is immutable once
deployed, so the escaping fix below could not reach `v0` and is the reason `v1`
exists.
None of what follows needs a key, a transaction or a gas budget. `Reapable`,
`Compactable` and `Bounty` are in the ABI precisely so the incentive is legible
to a reader *before* anyone signs anything: a bot decides whether to spend gas
entirely from free reads.

```bash
RPC=https://rpc.gno.land
hx() { printf '%s' "$1" | xxd -p | tr -d '\n'; }
q() { curl -s "$RPC/abci_query?path=%22$1%22&data=0x$(hx "$2")" | python3 -c '
import base64, json, sys
r = json.load(sys.stdin)["result"]["response"]
r = r.get("ResponseBase") or r
print(base64.b64decode(r["Data"]).decode() if r.get("Data") else r.get("Log"))'; }

R=gno.land/r/moul/x/reaper/v0
```

| Call | What it answers |
|---|---|
| `q vm%2Fqeval "$R.Reapable()"` | how many notes have expired, so a reaper knows whether to bother |
| `q vm%2Fqeval "$R.Compactable()"` | how many dead tree nodes a `Compact` would free: a separate call, and usually the larger payout |
| `q vm%2Fqeval "$R.Bounty().String()"` | the whole decision on one line: bytes, refund, gas, break-even, verdict |
| `q vm%2Fqstorage "$R"` | the chain's own figure for what this realm has locked, which is not the realm's estimate |
| `q vm%2Fqrender "$R:"` | the page |

`gnokey query vm/qeval -remote https://rpc.gno.land -data '<expr>'` is the same
call with a binary in front of it.

On 2026-09-22, with three expired notes sitting on the board:

```
$ q vm%2Fqeval "$R.Bounty().String()"
("37 bytes, refunds 0.0037 GNOT against 0.005 GNOT of gas, break-even 50 bytes: not worth it yet" string)

$ q vm%2Fqstorage "$R"
storage: 24435, deposit: 2443500
```

Read those two together, because the gap between them is the one thing this
realm cannot close from the inside. `Bounty` prices 37 bytes, estimated from
the length of the note bodies that have expired. `vm/qstorage` reports what the
chain has actually locked against the realm, 24,435 bytes and 2.4435 GNOT, for
everything it owns including its own source. **A realm cannot see that number
about itself; a querier can.** So price a reap off `Bounty` and settle against
the chain, never the other way round.

Three expired notes are also, deliberately, not worth reaping: 0.0037 GNOT of
refund against 0.005 GNOT of gas. The 50-byte break-even is the mechanism
working rather than failing. A bounty that paid out below its own cost would be
paying bots to churn.

### What it has actually paid, on mainnet

One `Reap` and one `Compact` have run on `gnoland-1`, at heights 228101 and
228113 on 2026-09-21. The chain's own numbers, not the realm's estimate:

| height | call | bytes freed | refunded | gas used |
|---|---|---|---|---|
| 228101 | `Reap(100)` | 3,945 | 0.3945 GNOT | 5,732,152 |
| 228113 | `Compact()` | 2,568 | 0.2568 GNOT | 4,684,883 |

At the floor gas price those two transactions cost 0.005732 and 0.004685 GNOT,
so the refund was **69x** and **55x** the cost of collecting it. The compaction
row is the one to notice: a second transaction, over notes that had already
been deleted, returned 65% as much again as the deletion itself.

Both were signed by the account that posted the notes, so what mainnet has
demonstrated so far is the accounting and not yet the stranger. The refund goes
to whoever signs, either way, which is exactly why the stranger case pays.

**The gas fee is flat, and sizing it is the reaper's whole job.** tm2 deducts
the declared `-gas-fee` in full in the ante handler and never refunds the
unused part, so a reap costs what you ask for and not what you spend. Both
transactions above asked for 1,000,000,000 gas and paid 1 GNOT to do 5.7 and
4.7 million gas of work, which turned a 69x win into a loss. Size `-gas-wanted`
to the batch and set `-gas-fee` at the floor price, which is what `Bounty`
already assumes.

The same queries run in CI. [`example_test.gno`](./example_test.gno) pins each
one, and it pins *only* queries for a reason worth knowing: an example function
takes no arguments, so it never receives a `cur realm` and can never `Post`,
`Reap` or `Compact`. What an example can reach is exactly what a reader of the
live realm can reach without a key.

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
and the board never emits one unescaped. One call does it:

```go
func summarize(body string) string {
	return ui.Excerpt(strings.ReplaceAll(body, "|", " "), 48)
}
```

[`ui.Excerpt`](https://github.com/moul/gno-contracts/blob/main/p/moul/kit/ui/ui.gno) owns both
halves, the length cap and the escaping, and does them in the order that is safe.
It delegates the escaping itself to
[`p/nt/markdown/sanitize`](https://github.com/gnolang/gno/tree/master/examples/gno.land/p/nt/markdown/sanitize/v0).

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

The escaper closes all five, and none of them were a bug in the incentive
design: the storage accounting was right, the rendering was not.

Two details are easy to get backwards, which is exactly why they live in
`ui.Excerpt` and not at this call site:

- **Cut first, escape second.** Escaping works by inserting backslashes, so
  cutting an already-escaped string can strand a trailing lone backslash that
  escapes the chrome appended after it.
- **Cut on a rune boundary.** Slicing a body at byte 48 splits a multi-byte
  character in half and puts invalid UTF-8 on the page. One emoji in a note was
  enough.

The general rule, for any realm that renders something a caller stored: reach
for `ui.Inline`, `ui.Cell` or `ui.Excerpt`, and drop to `sanitize.*` only for a
slot they do not cover (a multi-paragraph body, a URL, a code fence). Its
package doc carries the slot table.

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

![gno.land/r/moul/x/reaper/v1 dependency graph](https://raw.githubusercontent.com/moul/gno-contracts/main/_assets/gno.land/r/moul/x/reaper/v1/deps.png)

> 🧪 **Highly experimental — potentially vibe-coded.** Not audited; may break, change, or be removed at any time. Do not use with anything of value. Full disclaimer: [DISCLAIMER](https://github.com/moul/gno-contracts/blob/main/DISCLAIMER.md).

<!-- END GNOCONTRACTS FOOTER -->
