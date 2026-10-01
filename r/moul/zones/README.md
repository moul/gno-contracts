# zones

A curated registry of gno.land networks and the endpoints that reach them:
mainnet, the testnets, staging chains, anybody's gnodev. Anybody proposes a
zone; a curator approves, rejects or retires it, and verifies or flags its
endpoints. Every decision is recorded with who made it and when, and a
rejection, a retirement, a flag or an edit to an approved zone must also say
why, on the zone's page. Nothing is hidden while it waits: proposals and
unverified endpoints are listed, and labelled.

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
| `staging` | `staging` | rpc, gnoweb, **flagged**: neither answered when seeded, and the flag says what each returned |
| `moul-staging` | `moulstaging-1` | rpc, gnoweb, faucet, all verified |

## Read it from a node

The reads take plain values, so they work from `gnokey query vm/qeval` and from
another realm alike. An empty kind or status matches anything; a slug is
required wherever one is asked for.

```sh
gnokey query vm/qeval -remote https://rpc.gno.land \
  -data 'gno.land/r/moul/zones/v0.ListAddresses("onyx", "peer", "verified")'
```

| function | answers |
|---|---|
| `ListZones(status, kind)` | the zones, in the order they were proposed; `approved` is the official list |
| `GetZone(slug)` | one zone, and whether it exists |
| `ListEndpoints(slug, kind, status)` | one zone's endpoints, oldest first |
| `ListAddresses(slug, kind, status)` | the same, reduced to the address strings a config file wants |
| `GetEndpoint(id)` | one endpoint, and whether it exists |
| `IsCurator(addr)`, `Curators()` | who curates |
| `IsInvited(addr)`, `Invited()` | who has an open invitation to curate |

Turning these into a node's `config.toml` is deliberately not this realm's job.
It is public (`gnomod.toml` says why) so that a separate realm can import it and
do that.

## Write to it

| function | who |
|---|---|
| `ProposeZone(slug, chainID, title, description, kind, gnowebURL, rpcURL, genesisURL)` | anybody |
| `EditZone(slug, revision, chainID, ..., reason)` | a curator, or the proposer while pending. Before review the reason must be empty; on an approved zone it is required and replaces the review on record. Every edit bumps the zone's revision, and a new chain id sends its verified endpoints back to unverified. A rejected or retired zone is not editable |
| `ApproveZone(slug, revision, reason)` | a curator |
| `RejectZone(slug, revision, reason)`, `RetireZone(slug, revision, reason)` | a curator, reason required; the zone's verified endpoints go back to unverified |
| `RemoveZone(slug, revision)` | a curator, on a pending or rejected zone; or its proposer, on a pending one, while every endpoint on it is theirs and none is verified or flagged. One that was ever official is not removable; a retired one is kept until 128 newer retirements push it out |
| `RegisterEndpoint(slug, kind, addr, label)` | anybody on an approved zone; on a pending one, its proposer or a curator |
| `VerifyEndpoint(id, revision, reason)` | a curator, naming the zone revision they checked it against |
| `FlagEndpoint(id, reason)`, `UnverifyEndpoint(id, reason)` | a curator; a flag needs a reason |
| `RemoveEndpoint(id)` | a curator, or its registrant while it is unverified and 100 blocks after registering it: a verified or flagged endpoint is a record, and only a curator removes it |
| `AddCurator(addr)` | a curator; it is an invitation, at most 16 curators and invitations together |
| `AcceptCurator()` | the invited address, to take up the invitation |
| `RemoveCurator(addr)` | a curator; it withdraws an invitation, or removes a curator along with every invitation they sent. The last curator cannot be removed |

Every decision on a zone (edit, approve, reject, retire, remove) and every
verification takes its `revision`, the one you read (the zone page shows it,
and its action links carry it): if the zone changed since, its content or its
status, the call fails and you read it again. The `$help` links on each page
fill it in. A proposer edits or withdraws a pending zone only 100 blocks after it was
proposed or last edited (by anybody), and a registrant withdraws an endpoint
only 100 blocks after registering it, so neither can keep an entry out of a
curator's reach by changing it faster than they read.

**Curators are equals**: any one may remove any other, the admin included. That
is the trust a curator set is, and it is why there are few of them.

A storage deposit is refunded to whoever signs the transaction that frees it.
That is why a proposer cannot remove a zone carrying somebody else's endpoints,
and why a curator's removal collects what the remover did not pay.

## Pages

Every list is 25 rows a page (`?page=`), and a page reads only the records it shows:
`vm/qrender` is gas-metered, and a Render that outgrows it stops answering.
Paths are exact; anything else is Not found.

| path | shows |
|---|---|
| (root) | the official zones; `?status=retired` for the retired ones |
| `zone/<slug>` | one zone: its facts and revision, its last review, its endpoints; `?kind=peer` narrows them |
| `proposals` | pending proposals; `?status=rejected` for rejected ones, with the reason |

An official zone's gnoweb and genesis URLs are links; a proposal's show as
code, to copy and check, and so does one the zone also lists as a flagged web
endpoint, marked. RPCs and endpoint addresses are always code. An action link
is shown only when the call could pass the caps: no Propose with the queue
full, no Approve with the live registry full. Free
text has `@` and bare `g1` addresses neutralised, so a label cannot turn into a
profile link. A main RPC whose endpoint is flagged is marked so wherever it is
shown, and the printed `gnokey` line leaves it out.
