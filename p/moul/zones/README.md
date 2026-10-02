# `gno.land/p/moul/zones/v0`

**The content model of a curated registry of gno.land networks**: `Zone`,
`Endpoint`, their validation, and the curation state machine, held by a
`Registry`.

```go
import "gno.land/p/moul/zones/v0"

r := zones.NewRegistry()
must(r.Propose(proposer, height, "onyx", zones.Info{ChainID: "onyx-1", Title: "Onyx",
	Kind: zones.Testnet, RPCURL: "https://rpc.onyx.testnets.gno.land"}))
z, _ := r.Zone("onyx")
must(r.ReviewZone("onyx", zones.Approved, z.Revision, curator, height, ""))
z, _ = r.Zone("onyx") // the approval bumped the revision
id, err := r.Register(proposer, height, "onyx", zones.Peer,
	"g1x5mlj5ava0dw9vkf4j6admjlzswm6f06p44krn@seed-1.onyx.testnets.gno.land:26656", "gno core")
must(err)
must(r.ReviewEndpoint(id, zones.Verified, z.Revision, curator, height, "answers onyx-1"))
r.Endpoints(zones.EndpointFilter{Zone: "onyx", Kind: zones.Peer, Status: zones.Verified}) // that one peer
```

A **zone** is one network: chain id, title, description, kind (`mainnet`,
`testnet`, `devnet`, `local`), its main RPC, gnoweb and genesis URLs. An
**endpoint** is one way into a zone: `rpc`, `gnoweb`, `seed`, `peer`, `indexer`,
`faucet` or `explorer`, `unverified` until a curator says otherwise.

The live registry is [`r/moul/zones`](../../../r/moul/zones), which holds one
`Registry` and decides who may write to it.

**It decides nothing about who may act, deliberately.** Every write that
records a decision takes the acting address and the height as arguments (the
two removals take neither: who may remove is the holder's call). Whether that
address is a curator, the proposer, or nobody is the holding realm's call, so
the same model can move under a DAO or a system realm later without a line
changing here.

## The curation policy

| decision | from | reason | also |
|---|---|---|---|
| approve | pending, rejected, retired | optional | |
| reject | pending | **required** | verified endpoints go back to unverified |
| retire | approved | **required** | verified endpoints go back to unverified |
| edit | pending, approved | none before review, **required** after | a new chain id un-verifies endpoints |
| remove | pending, rejected | | endpoints go with it |
| verify an endpoint | any, the same one only with a new reason | optional | zone pending or approved |
| unverify an endpoint | any, the same one only with a new reason | optional | |
| flag an endpoint | any, the same one only with a new reason | **required** | |

Every endpoint verdict names `VerdictRevision(zone, endpoint)`, the later of the
zone's `Revision` and the endpoint's own, both from the one counter that never
repeats: so it fails if the zone changed (a verification checks the endpoint
answers for this zone's chain id) or another curator ruled on the endpoint
since it was read (a verdict landing unseen would reverse theirs).

- **Every decision on a zone binds to the zone as read**: its fields and its
  status. Every edit bumps the
  zone's `Revision`, registry-wide and never reused (not even by a zone removed
  and proposed again under the same slug). Approving, rejecting, retiring,
  editing and removing all name it, so an edit that lands between the reading
  and the decision makes the decision fail, instead of attaching a name to text
  nobody read. Every status change bumps it too, so an approval opened before a
  colleague's rejection fails rather than reversing it. Verifying an endpoint
  binds the same way, to the revision it was checked against: what was checked
  is that it answers for this zone's chain id. An edit that changes nothing is
  refused, so a revision only moves when something did. An endpoint's verdict
  is not part of the zone and does not move it: a flag on the zone's own main
  RPC shows on the zone, it does not invalidate an approval in flight.
- **Only a pending or approved zone is editable.** An edit before review takes
  no reason. An edit to an approved zone is a curator decision: the reason is
  required and replaces the review on record. A changed chain id, on any zone,
  sends every verified endpoint back to unverified, because what was verified
  was that it answered for the old one. A reset caused by an edit to a pending
  zone by its own proposer records nobody, because that is not a review:
  `ReviewedBy` is empty and `Reason` says why. Every other reset records the
  editor or the reviewer who caused it.
- **Nothing goes back to pending.** A rejected zone is approved after all,
  removed, or pushed out by 64 newer rejections.
- **A zone that was ever official is never removed by a caller.** An approved
  one is retired, and a retired one is kept until 128 newer retirements push it
  out, so whoever still holds its chain id can find out what happened to it.

## What a field accepts

Validated at write time, not escaped at render time, for everything that is
also an index key, a URL segment or a config-file line:

- **Slug**: 2 to 32 of `[a-z0-9-]`, alphanumeric at both ends.
- **Chain id**: 1 to 50 of `[A-Za-z0-9._-]`.
- **URL**: visible ASCII with none of `` <>"'`()[]{}|\^# ``, no credentials,
  no `%` without two hex digits after it, no `&name;` shape, a host that is a
  DNS name or an IPv4 address (anything a browser would read as IPv4, like
  `0x7f.1`, must be a valid dotted quad), an optional port of 1 to 65535 in
  digits, and a scheme from a short list. A zone's main RPC is `http`, `https`
  or `tcp` with no path, query or trailing slash, which is what `gnokey -remote`
  dials; an `rpc` endpoint also takes `ws`, `wss` and a path. A `%` never
  escapes a character that needs no escaping, and a path has no `.` or `..`
  segment, so a URL has one spelling. A host that names a different machine
  for every reader is refused except on a `local` zone: a name with no dot,
  `.localhost`, `.local`, `.internal`, `.localdomain`, the RFC 6761 names
  `.test`, `.example` and `.invalid`, the never-delegated `.lan`, `.home`,
  `.corp`, `.mail`, `.intranet`, `.private`, `.onion`, `.alt`, every `.arpa`
  name (infrastructure, never a public service), and IPv4 "this network", loopback, private, link-local,
  CGNAT, IETF-protocol, documentation, benchmarking, multicast and reserved
  ranges. A zone that leaves the `local` kind drops every endpoint on one, in
  the same edit. An IPv4 host has no terminal dot.
- **Peer**: `<node id>@<host>:<port>`, the shape `p2p.persistent_peers` takes,
  the node id a lowercase g1 address (tm2 compares node ids byte for byte), and
  no terminal dot on an IPv4 host (Go's dialer cannot use one, so URLs refuse
  it too).
- **Address** (proposer, registrant, reviewer): a valid g1 address in lowercase.
  bech32 also decodes the uppercase form, and here it would be a second identity.
- **Free text** (title, description, label, reason): one line, bounded in
  characters (so at most four times as many bytes), valid UTF-8, with no control
  character, no invisible, format, private-use or unassigned character, no
  variation selector, no enclosing mark (it draws a badge's frame around any
  character), no run of more than four other combining marks, none of the
  status glyphs a Render draws nor their look-alikes, and, unless it is empty,
  something visible. Refused rather than stripped, so what is stored is what is
  shown. It must still be escaped by whoever renders it. Two consequences:
  the zero-width joiner and non-joiner are refused, so the Persian and Sinhala
  spellings and the emoji sequences that need them cannot be written; and
  "assigned" means in the chain's own Unicode tables, 15.0, so a character
  assigned since is refused on chain though `gno test` (which uses the host's
  tables) accepts it.

An endpoint is stored in canonical spelling (scheme lowercased, a peer
lowercased whole without its host's terminal dot) and deduplicated on
`Canonical`: scheme and host lowercased, a terminal dot, a default port, an
empty path before a query, an empty query's `?` and a bare `/` dropped, `%XX`
hex uppercased, an rpc `tcp://` read as the `http://` gnokey dials, anything
meaningful after the host kept as typed. The same address under two kinds is two
endpoints.

## Bounds

The **live registry**, pending and approved zones together, holds at most 256.
Rejected and retired zones are kept for the record but do not count against it:
each state keeps at most 64 and 128, and the next one in drops the zone that has
been in that state longest, endpoints and all. So no flood, no curator and no
amount of time fills the registry for good.

**Per-address caps** make one address cheap to ignore: 4 pending proposals, 16
endpoints on a zone. Neither stops a flood from many addresses, so **the review
queue has an admission gate of its own**: 64 pending zones in all, 64 endpoints
per zone waiting for a verdict, under a hard 128 per zone. A flagged endpoint
has its verdict and leaves the queue, so curators keep warnings instead of
deleting them to make room. The gate is checked where something enters, so a
review or a reset can push a count past it. A flood fills the queue and never
crowds out an approved zone or a verified endpoint, and `ProposeExempt` and
`RegisterExempt` skip the gate and the per-address caps (not the hard caps) for
the reviewers the holding realm trusts, so a full queue never locks out the
people who clear it. Each entry costs its sender a storage deposit, refunded to
whoever signs the transaction that frees it (on a chain with transfers locked,
to the storage fee collector instead), so a flooder who withdraws first gets it
back: a bond, not a fee.

## Storage

Records live in a B+ tree, the keyed, ordered container EFFECTIVE_GNO recommends
for iteration and pagination (671 B per entry at fanout 32), with ids that are
never reused. Every tree here, `kit/index`'s included, is at fanout 32, not 128:
a removal shifts every later value in its leaf, and each shifted value is
rewritten, about 90k gas apiece for a number and 230k for a pointer on a real
node, so a smaller leaf bounds what one removal costs. `kit/store` has that
shape on an avl tree (2,029 B), and on an immutable path the choice is
permanent. Three B+ trees hold an id per key: slug, the endpoint dedup key (a
128-bit hash of the canonical address rather than a second copy of it), and the
order zones entered their state. Three hold a count per key: pending proposals
per proposer, endpoints per registrant on a zone, flagged endpoints per zone.
The other five are [`kit/index`](../kit/index): status, approved-by-chain-id,
and for endpoints zone, zone-and-kind and not-verified. Every one is written in
the same method as its record; counts come from the indexes without reading a
record, and a page reads the records on it only (the bucket's id list, at most
256 or 128 ids, is read whole). The heaviest write, measured on a node at the
caps with full-length text, is an edit taking a local zone with 128 private
endpoints off `local`, about 0.65B gas, because each dropped endpoint unwinds
its own index entries; a retirement that evicts a full zone is about 0.38B. Both
are well under a block's gas.
