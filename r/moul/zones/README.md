# zones

A curated registry of gno.land networks and the endpoints that reach them:
mainnet, the testnets, staging chains, anybody's gnodev. Anybody proposes a zone
or registers an endpoint on one; a curator approves, rejects, retires, verifies
or flags it, and every decision carries a reason the public reads on the zone's
page. Nothing is hidden while it waits: proposals and unverified endpoints are
listed, and labelled.

The model, validation and state machine are [`p/moul/zones`](../../../p/moul/zones).
This realm owns only who may write, and the pages.

## It ships with four zones

All approved at deploy, every address probed on 2026-10-01. Peers are the
`persistent_peers` each network's `VALIDATOR.md` publishes in the gnolang/gno
monorepo.

| slug | chain id | endpoints |
|---|---|---|
| `mainnet` | `gnoland-1` | rpc, gnoweb, 2 peers, indexer, explorer, all verified |
| `onyx` | `onyx-1` | rpc, gnoweb, 2 peers, indexer, faucet, explorer, all verified |
| `staging` | `staging` | rpc, gnoweb, **unverified**: neither answered when seeded |
| `moul-staging` | `moulstaging-1` | rpc, gnoweb, faucet, all verified |

## Read it from a node

The reads take plain strings, so they work from `gnokey query vm/qeval` and from
another realm alike. An empty argument matches anything.

```sh
gnokey query vm/qeval -remote https://rpc.gno.land \
  -data 'gno.land/r/moul/zones/v0.ListAddresses("onyx", "peer", "verified")'
```

| function | answers |
|---|---|
| `ListZones(status, kind)` | the zones, in the order they were proposed; `approved` is the official list |
| `GetZone(slug)` | one zone, and whether it exists |
| `ListEndpoints(slug, kind, status)` | one zone's endpoints, oldest first; the slug is required |
| `ListAddresses(slug, kind, status)` | the same, reduced to the address strings a config file wants |
| `GetEndpoint(id)` | one endpoint, and whether it exists |
| `IsCurator(addr)`, `Curators()` | who curates |

Turning these into a node's `config.toml` is deliberately not this realm's job.
It is public (`gnomod.toml` says why) so that a separate realm can import it and
do that.

## Write to it

| function | who |
|---|---|
| `ProposeZone(slug, chainID, title, description, kind, gnowebURL, rpcURL, genesisURL)` | anybody |
| `EditZone(..., reason)` | a curator, or the proposer while pending; on an approved zone the reason is required and replaces the review on record, and a new chain id sends its verified endpoints back to unverified; a rejected or retired zone is not editable |
| `RemoveZone(slug)` | a curator, or the proposer while every endpoint on it is theirs, on a pending or rejected zone; one that was ever official is kept |
| `RegisterEndpoint(slug, kind, addr, label)` | anybody, on a pending or approved zone |
| `RemoveEndpoint(id)` | its registrant or a curator |
| `ApproveZone`, `RejectZone`, `RetireZone` | a curator |
| `VerifyEndpoint`, `FlagEndpoint`, `UnverifyEndpoint` | a curator |
| `AddCurator`, `RemoveCurator` | a curator; the last one cannot be removed |

## Pages

| path | shows |
|---|---|
| `` | the official zones, the retired ones, how to read it |
| `zone/<slug>` | one zone: its facts, its review, its endpoints grouped by kind |
| `proposals` | pending proposals, and rejected ones with the reason |
