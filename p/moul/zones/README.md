# `gno.land/p/moul/zones/v0`

**The content model of a curated registry of gno.land networks**: `Zone`,
`Endpoint`, their validation, and the curation state machine, held by a
`Registry`.

```go
import "gno.land/p/moul/zones/v0"

r := zones.NewRegistry()
err := r.Propose(caller, height, "onyx", zones.Info{ChainID: "onyx-1", Title: "Onyx", Kind: zones.Testnet,
	RPCURL: "https://rpc.onyx.testnets.gno.land"})
err = r.ReviewZone("onyx", zones.Approved, curator, height, "")
id, err := r.Register(caller, height, "onyx", zones.Peer,
	"g1x5mlj5ava0dw9vkf4j6admjlzswm6f06p44krn@seed-1.onyx.testnets.gno.land:26656", "gno core")
err = r.ReviewEndpoint(id, zones.Verified, curator, height, "answers onyx-1")
r.Endpoints(zones.EndpointFilter{Zone: "onyx", Kind: zones.Peer, Status: zones.Verified}) // → that one peer
```

A **zone** is one network: chain id, title, description, kind (`mainnet`,
`testnet`, `devnet`, `local`), its main RPC, gnoweb and genesis URLs. An
**endpoint** is one way into a zone: `rpc`, `gnoweb`, `seed`, `peer`, `indexer`,
`faucet` or `explorer`, registered by anybody and `unverified` until a curator
says otherwise.

The live registry is [`r/moul/zones`](../../../r/moul/zones), which holds one
`Registry` and decides who may write to it.

**It decides nothing about who may act, deliberately.** Every write takes the
acting address and the height as arguments. Whether that address is a curator,
the proposer, or nobody is the holding realm's call, so the same model can move
under a DAO or a system realm later without a line changing here.

The curation policy, which is the part worth reading before you hold one:

| decision | from | reason |
|---|---|---|
| approve | pending, rejected, retired | optional |
| reject | pending | **required** |
| retire | approved | **required** |
| verify / unverify an endpoint | any other verdict | optional |
| flag an endpoint | any other verdict | **required** |

- **Only a pending or approved zone is editable.** Editing an approved one is
  a curator decision: the reason is required and replaces the review on record,
  and a changed chain id sends every verified endpoint back to unverified,
  because what was verified was that it answered for the old one.
- **Nothing goes back to pending.** A proposer who disagrees with a rejection
  removes the zone and proposes it again.
- **A zone that was ever official is never removed.** An approved one is
  retired, and a retired one is kept. The record of it having been official
  survives, which is what a node operator still holding its
  chain id needs to find.
- **Slugs, chain ids, URLs and peer addresses are validated at write time**, not
  escaped at render time. They are also index keys, URL segments and config file
  lines, so a pipe, a bracket or a quote in one would break more than the page.
  URLs are printable ASCII with no `<>"'`()[]{}|\^`, no credentials, a host
  that is a DNS name or IPv4 address, an optional port in 1..65535, and a scheme
  from a short list. A zone's main RPC is `http`, `https` or `tcp`, what
  `gnokey -remote` dials; an `rpc` endpoint also takes `ws` and `wss`. A peer is
  `<g1 node id>@<host>:<port>`, the shape `p2p.persistent_peers` takes.
- **Free text (title, description, label, reason) is one line, rune-bounded**,
  and must be escaped by whoever renders it.
- **Endpoint dedup compares the `Canonical` form**: scheme and host lowercased,
  path and query kept as typed, because only the first two are case-insensitive.
  The same address under two kinds is two endpoints.

Bounded in three layers. **Hard caps** bound the storage: 256 zones, 512
endpoints per zone. **Per-address caps** make one address cheap to ignore: 4
pending proposals, 32 endpoints per zone. Neither stops a flood from many
addresses, because an address is not an identity, so **the review queue has a
ceiling of its own**: 64 pending zones in all, 128 unverified endpoints per
zone. A flood can fill the queue and nothing above it, so it never crowds out an
official zone or a verified endpoint; a curator clears it with `RemoveZone` /
`RemoveEndpoint`, and the storage deposit every entry costs its sender is the
only admission price a permissionless list has. Removing a zone removes its
endpoints and gives the deposit back.

Storage is a [`kit/store`](../kit/store) for each record type plus six
[`kit/index`](../kit/index) lookups (slug, pending-by-proposer, zone, dedup key,
registrant, unverified-by-zone), every one written in the same method as its
record.
