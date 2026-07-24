# Personal Blog

> ⚠️ **Experimental — generated with no human supervision.** This realm was
> produced automatically by an MCP-driven agent to exercise the gno MCP server
> and tooling, and to generate test content for gno compilers, linters and
> formatters. **Not audited. Not for production.** Full context & folder README:
> [r/moul/daily/x](https://github.com/moul/gno-contracts/blob/main/r/moul/daily/x/README.md)

---


A multi-author on-chain blog realm for gno.land. Anyone can publish a post; each
post records its author (the calling address) and the block height at which it
was published. Posts are stored persistently and rendered newest-first, with a
dedicated page for each post's full text.

**Realm path:** `gno.land/r/REPLACE_ADDR/blog`

## Example calls

Publish a post (state-mutating, crossing function):

```
gnokey maketx call -pkgpath "gno.land/r/REPLACE_ADDR/blog" \
  -func Publish -args "My first post" -args "Hello, gno.land!" \
  -gas-fee 1000000ugnot -gas-wanted 2000000 -broadcast -chainid test13 KEY
```

Read views (no transaction needed):

- Root — list all posts, newest first: render `gno.land/r/REPLACE_ADDR/blog`
- Single post by id: render `gno.land/r/REPLACE_ADDR/blog:/0`

`PostCount()` returns the total number of published posts.
