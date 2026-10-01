# `gno.land/p/moul/zones/v0`

**The content model of a curated registry of gno.land networks**: `Zone`,
`Endpoint`, their validation, and the curation state machine, held by a
`Registry`.

```go
import "gno.land/p/moul/zones/v0"

r := zones.NewRegistry()
r.Propose(caller, height, "onyx", zones.Info{ChainID: "onyx-1", Title: "Onyx", Kind: zones.Testnet,
	RPCURL: "https://rpc.onyx.testnets.gno.land"})
r.ReviewZone("onyx", zones.Approved, curator, height, "")
id, _ := r.Register(caller, height, "onyx", zones.Peer, "g1…@seed-1.onyx.testnets.gno.land:26656", "gno core")
r.Endpoints(zones.EndpointFilter{Zone: "onyx", Kind: zones.Peer, Status: zones.Verified})
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

- **Nothing goes back to pending.** A proposer who disagrees with a rejection
  removes the zone and proposes it again.
- **An approved zone is retired, never rejected or removed.** The record of it
  having been official survives, which is what a node operator still holding its
  chain id needs to find.
- **Slugs, chain ids, URLs and peer addresses are validated at write time**, not
  escaped at render time. They are also index keys, URL segments and config file
  lines, so a pipe, a bracket or a quote in one would break more than the page.
  URLs are printable ASCII with no `<>"'`()[]{}|\^`, no credentials, and a scheme
  from a short list (`rpc` also takes `ws`, `wss` and `tcp`). A peer is
  `<g1 node id>@<host>:<port>`, the shape `p2p.persistent_peers` takes.
- **Free text (title, description, label, reason) is one line, rune-bounded**,
  and must be escaped by whoever renders it.
- **Endpoint dedup is case-insensitive** on `zone|kind|address`, because a DNS
  name is, and the same address under two kinds is two endpoints.

Bounded everywhere a stranger could grow it: 256 zones, 4 pending proposals per
proposer, 512 endpoints per zone, 32 per registrant per zone. The per-address
caps are what keep the registry open to the next person once somebody has
spammed it. Removing a zone removes its endpoints and gives the deposit back.

Storage is a [`kit/store`](../kit/store) for each record type plus five
[`kit/index`](../kit/index) lookups (slug, pending-by-proposer, zone, dedup key,
registrant), every one written in the same method as its record.
