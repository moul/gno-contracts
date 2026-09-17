# `gno.land/r/moul/wiki/v0`

An open, on-chain encyclopedia. Anyone can create or edit a page, every edit is
a signed revision, and the whole history is public and tamper-evident.

A thin realm over [`p/moul/wiki/v0`](../../../../p/moul/wiki/v0): the library
owns content (titles, revisions, wikilinks, categories, diffs, rendering), this
realm owns **authority** (who may write what) and the chain wiring (block
height, block time, the calling address, transaction links). There is no policy
in the library and no content logic here.

## Writing

| call | who |
|---|---|
| `Edit(title, body, summary)` | anyone, subject to the page's protection |
| `Revert(title, rev, summary)` | same |
| `Protect(title, "open"\|"semi"\|"locked")` | steward |
| `Move(from, to, reason)` | steward |
| `Blank(title, reason)` | steward |
| `Purge(title)` | steward |
| `AddEditor` / `RemoveEditor` / `Ban` / `Unban` / `SetCooldown` | steward |

```sh
gnokey maketx call -pkgpath gno.land/r/moul/wiki/v0 -func Edit \
  -args 'Gno land' -args 'gno.land is a chain that runs [[Gno]].
[[Category:Chains]]
' -args 'expand the intro' \
  -gas-fee 1000000ugnot -gas-wanted 20000000 -broadcast -chainid <id> <key>
```

The body is markdown plus `[[wikilinks]]`, `[[Category:Name]]` and a
`#REDIRECT [[Target]]` first line; the syntax table is in the library README.

## Reading

| route | page |
|---|---|
| `` | front page: counts and recent changes |
| `Title` | the article |
| `Title/history?offset=` | revisions, newest first |
| `Title/raw` | current source with its SHA-256 |
| `Title/rev/<id>` | one stored revision |
| `Title/diff?from=&to=` | a line diff |
| `Category:Name` | the category and its members |
| `Special:AllPages?ns=` · `Special:Categories` · `Special:RecentChanges` · `Special:Backlinks?page=` · `Special:Stats` | listings |

`Render` is total: a malformed path returns a page, never an abort.

## Authority

One `ownable.Ownable` steward, transferable, so the wiki can be handed to a DAO
realm without redeploying. Three protection levels: `open` (anyone), `semi`
(an explicit editor list), `locked` (steward only). A page that does not exist
yet is open to anyone.

The real anti-vandalism mechanism is not the ban list: **the storage deposit
makes the editor fund every byte they add**, and a revert releases it again.
`SetCooldown` adds a per-address minimum block gap on top, off by default.

Blanking is the deletion a chain can honestly offer. The page stops rendering
and stops costing rent as its bodies age out, while the revision spine stays as
proof that something was there and who removed it. `Purge` releases the
retained bytes immediately. Neither removes the transactions that wrote the
content: on a public chain, "delete" means "stop serving", not "unhappen".

## Cost

Storage deposit is 100ugnot per byte, locked while the bytes are held and
released when they are removed. A 5 KB article is therefore about 0.5 GNOT of
deposit for its current revision, plus roughly 0.02 GNOT for each revision's
permanent spine, and the default retention window keeps three bodies. Every
page's footer shows its own held bytes and deposit, and `Special:Stats` shows
the wiki's.

## Seeded content

`init` writes four linked pages (`Gno land`, `Gno`, `Tendermint2`,
`Help:Editing`) so a fresh deploy renders a connected wiki instead of an empty
index.
