# gnoblog

The local half of [`r/moul/blog`](../../r/moul/blog/README.md): write markdown
in a directory, see the index before anyone else does, push only what changed.

Standard library only: no `gnoclient`, no cgo, no second `go.mod`. It reads the
chain over plain JSON-RPC `abci_query`, builds an unsigned transaction document,
and hands it to `gnokey`, which signs it and prompts on your terminal for a
passphrase this process never sees. It holds no key and signs nothing.

## The content directory is not in this repository

There is no default path to it and there is not going to be one. Pass
`-content`, or set `GNOBLOG_CONTENT`. The posts are public once published; the
directory they are drafted in is not, and a tool that shipped its path would be
publishing where the drafts are kept.

```
<dir>/<slug>.md   a post
<dir>/intro.md    the markdown shown above the index, no front matter
```

A post is front matter then markdown:

```markdown
---
title: Sharing mygnoscan
date: 2026-09-23
tags: mygnoscan, tooling
---

The post.
```

Three keys, all scalars, parsed without a YAML dependency on purpose: the
hash has to be reproducible from the bytes, and a YAML library is a way for a
value to change without the file changing.

## The loop

```sh
export GNOBLOG_CONTENT=/where/the/markdown/lives

go -C tools tool gnoblog posts      # what is here: date, slug, bytes, hash
go -C tools tool gnoblog preview    # the index, as the realm will lay it out
go -C tools tool gnoblog status     # what differs from the chain, one query
go -C tools tool gnoblog tx         # publish exactly that, one signature
```

**`status` is the review step, and it is the last point at which a post is still
private.** `tx` writes `.gnoblog-tx.json` next to the content directory and then
signs and broadcasts it, so read `status` first and mean it.

`tx -print` writes the two commands out and runs nothing. It does not exist as a
safety net, `status` is that; it exists for the case where the signing happens
somewhere else.

| command | what it does |
| --- | --- |
| `posts` | the local posts: date, slug, bytes, hash, title |
| `preview` | render the index, or `-post SLUG` for one post; `-out FILE` to write it |
| `status` | diff the content directory against the chain manifest, one query, no bodies |
| `tx` | publish the difference: one document, one signature, one broadcast |

`tx` flags: `-all` pushes everything rather than the difference, `-print` writes
the commands instead of running them, `-prune` also emits `Delete` for a post on
chain with no local file, `-out` moves the document, `-gas-wanted` / `-gas-fee` /
`-max-deposit` override the estimates.

## `-all` is the redeploy button

`r/moul/blog` is `private = true`, which is what lets its code be replaced at
the same path forever. A redeploy re-runs `init()` and **wipes every post**.

That is recoverable and only because of this tool: `tx -all` rebuilds the whole
blog as one transaction, without asking the chain what it has, which is the
point, since right after a redeploy the chain has nothing and a diff would
answer "everything" one round trip later.

## One signature, N posts

A post body is measured in kilobytes, so the `-args "$(cat file)"` shape
[`gnohome`](../gnohome/README.md) offers is not available here: it has to quote
for `/bin/sh`, command substitution eats the trailing newline, and `ARG_MAX` is
a real ceiling. In a tm2 transaction document the body is a literal JSON
string, so there is no shell in the loop at all.

A tm2 transaction carries a list of messages and `gnokey sign` signs the
document rather than the message, so publishing three posts is one passphrase
prompt and one atomic broadcast.

That signature binds chain id, account number and sequence, which is also why
`tx` broadcasts rather than printing: the gap between reading a pasted command
and running it is a window in which anything else this key signs voids the
document, and nothing was checking the paste anyway.

## The hash both halves have to agree on

`status` decides whether a post needs a transaction by comparing a sha256 over
`title \n date \n tags \n body` against the one `Manifest()` reports. Nothing
can run gno and Go in the same test, so the agreement is pinned from both
sides: the realm's test asserts the record, and `TestRecordHashIsPinnedAgainstTheRealm`
pins its digest as a literal.

If that test ever fails, the realm's `record()` moved, and until both sides
move together `status` will report every post as up to date while the chain
holds the old text.
