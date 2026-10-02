# zones

A curated registry of gno.land networks and the endpoints that reach them:
mainnet, the testnets, staging chains, anybody's gnodev. Anybody proposes a
zone; a curator approves, rejects or retires it, and verifies or flags its
endpoints. The latest decision on each is recorded with who made it and when, and a
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
do that. Two things an importer must know: a slice these return is read-only in
the importing realm, elements included (copy it before sorting or changing it;
a struct returned on its own is already the caller's; a slice the importer
keeps in its own state stays this realm's object, so copy it before storing it
too), and a kind or status the
`p/moul/zones` `Parse` functions do not accept, or a blank slug, panics, which no `recover` in the
caller catches, so check one taken from a query string with them first.

## Write to it

| function | who |
|---|---|
| `ProposeZone(slug, chainID, title, description, kind, gnowebURL, rpcURL, genesisURL)` | anybody; a curator also when the review queue is full, and into the registry's last 16 places |
| `EditZone(slug, revision, chainID, ..., reason)` | a curator, or the proposer while pending. Before review the reason must be empty; on an approved zone it is required and replaces the review on record. Every edit bumps the zone's revision, and a new chain id sends its verified endpoints back to unverified. Leaving `local` drops every endpoint on a private host, at most 64 in one edit (more, remove some first), and is refused while one carries a curator's ruling (a curator removes it first; a verified one its registrant may withdraw); the proposer's edit only drops endpoints that are theirs and that they could withdraw on their own. A rejected or retired zone is not editable |
| `ApproveZone(slug, revision, reason)` | a curator |
| `RejectZone(slug, revision, reason)`, `RetireZone(slug, revision, reason)` | a curator, reason required; the zone's verified endpoints go back to unverified. Rejecting a rejected zone, or retiring a retired one, with a new reason restates it; so does approving an approved one |
| `RemoveZone(slug, revision)` | a curator, on a pending or rejected zone; or its proposer, on a pending one, 100 blocks after it was proposed or last edited, while every endpoint on it is theirs and one they could withdraw on its own (below). One that was ever official is not removable; a retired one is kept until 128 newer retirements push it out |
| `RegisterEndpoint(slug, kind, addr, label)` | anybody on an approved zone; on a pending one, its proposer or a curator. The zone's own main RPC under `rpc` and gnoweb under `gnoweb` only a curator lists, or the proposer while the zone is pending (every proposer right ends at approval), since the page marks those URLs by that listing's verdict. An edit cannot make a stranger's listing the zone's own either: when it changes the main RPC or gnoweb to a URL a stranger (on an approved zone, the proposer too) lists under that kind, on a curator's edit the listing is dropped if nobody ruled on it (so pre-listing a zone's next URL cannot hold its move off) and the edit is refused if a curator did; a proposer's edit refuses rather than drop what is not theirs, and a flagged listing refuses the edit whoever holds it. A curator also registers past the review queue and the 16-per-address cap, and into the last 16 of the zone's 128 places, which a registration through the queue may not take |
| `VerifyEndpoint(id, zoneRevision, revision, reason)` | a curator, naming the endpoint's revision (the endpoint table's column) and the zone's (the zone page's), both as read |
| `FlagEndpoint(id, revision, reason)`, `UnverifyEndpoint(id, revision, reason)` | a curator, naming the endpoint's revision as read. A flag needs a reason; any verdict given again with a new reason restates it |
| `ClearUnreviewed(slug, throughRevision)` | a curator: removes, in one call, every endpoint on the zone that nobody ruled on and that was registered through the review queue, not past it by a curator (never more than the 64 the queue holds), up to the revision named, on every page and every kind (the link on the zone's unfiltered page carries the revision it was rendered at, so nothing registered after is touched). For a flood that withdraws and registers again faster than one removal at a time |
| `RemoveEndpoint(id, revision)` | a curator; or its registrant, on a pending or approved zone, 100 blocks after registering it, unless a curator flagged or unverified it (a reset, which a chain-id edit, a rejection or a retirement makes, leaves the withdrawal a verified one had). Naming the revision means a removal fails if a verdict landed since. A verified endpoint its registrant may take down; a flagged or curator-unverified one is a warning, and everything on a rejected or retired zone is a record: only a curator removes those |
| `AddCurator(addr)` | a curator; it is an invitation, at most 16 curators and invitations together |
| `AcceptCurator()` | the invited address, to take up the invitation |
| `RemoveCurator(addr)` | a curator; it withdraws an invitation, or removes a curator along with every invitation they sent. The last curator cannot be removed |

Every decision on a zone (edit, approve, reject, retire, remove) takes its
`revision`, the one you read (the zone page shows it, and its action links carry
it): if the zone changed since, its content or its status, the call fails and
you read it again. A verdict on an endpoint, and its removal, take the
endpoint's own revision (the endpoint table's column), so they fail if another
curator ruled on it since; a verification also takes the zone's. The two are
named apart: one number combined from two reads could pair a stale value with a
fresh one. The `$help` links fill a revision in; an edit, a verdict, a
restated decision and an endpoint's removal have no link, so copy them from the
zone page. A zone's
revision covers its own fields and status, not its endpoints' verdicts. A
proposer edits or withdraws a pending zone only 100 blocks (`ReviewWindow`)
after it was proposed or last edited, by anybody, and a registrant withdraws an
endpoint only 100 blocks after registering it: a rate bound (100 blocks is
minutes), so neither can change an entry every block.

**Curators are equals**: any one may remove any other, the admin included. That
is the trust a curator set is, and it is why there are few of them. A removed curator keeps what they registered, a listing of a zone's own
URL included, until a curator removes it.

A storage deposit is refunded to whoever signs the transaction that frees it
(on a chain with transfers locked, it goes to the storage fee collector). That
is why a proposer cannot remove a zone carrying somebody else's endpoints, and
why a curator's removal collects what the remover did not pay.

## Pages

Every list is 25 rows a page (`?page=`), and a page reads the records it shows
plus a bounded handful of lookups (each row's main RPC verdict, the flags on a
zone's own URLs, the zone serving the current chain for the printed command,
the curators), never a whole list: `vm/qrender` is
gas-metered, and a Render that outgrows it stops answering.
Paths are exact, up to slashes at either end; anything else is Not found.

| path | shows |
|---|---|
| (root) | the official zones; `?status=retired` for the retired ones |
| `zone/<slug>` | one zone: its facts and revision, its last review, its endpoints; `?kind=peer` narrows them |
| `proposals` | pending proposals; `?status=rejected` for rejected ones, with the reason |

An approved zone's gnoweb and genesis URLs are links; any other zone's show as
code, to copy and check. A main RPC or gnoweb URL the zone also lists, under
that same kind, as a flagged endpoint is code and marked wherever it is shown,
and the printed `gnokey` line leaves out a main RPC so marked. Only that kind's
flag counts: a listing under another kind is anybody's to make, so its flag
never marks the zone's own URL, and under its own kind only a curator lists it
(or the proposer, while pending). RPCs and endpoint addresses are always code. An action link
is shown only when the call could pass the caps, and where a cap is full a note
says which cap is full; a full review queue still takes a curator's call,
so its link stays, labelled for curators, and a zone with endpoints awaiting
review offers curators, on its unfiltered page and only while something is
clearable, a Clear link that says how many it clears and that it reaches all
pages and kinds, bound to the revision the page was rendered at. Where a
Rejection or a Retirement would evict the oldest record of its state, the page
says so beside it. Addresses are shown in full everywhere,
never shortened: an 8+4 shortening is within reach of a vanity grinder who
wants to look like a curator. Free text has `@` and bare `g1` addresses
neutralised, so a label cannot turn into a profile link.
