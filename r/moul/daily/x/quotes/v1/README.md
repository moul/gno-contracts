# Quote of the Moment

> ⚠️ **Experimental — generated with no human supervision.** This realm was
> produced automatically by an MCP-driven agent to exercise the gno MCP server
> and tooling, and to generate test content for gno compilers, linters and
> formatters. **Not audited. Not for production.** Full context & folder README:
> [r/moul/daily/x](https://github.com/moul/gno-contracts/blob/main/r/moul/daily/x/README.md)

---


A community quote board realm for gno.land (test13, gno 0.9). Anyone can submit
a quote; each entry records the text, the submitter's address, and the block
height at submission. The board ships pre-seeded with a handful of Stoic quotes
so a fresh deploy renders nicely, and the rendered page rotates a "featured"
pick deterministically as the chain advances.

- **Realm path:** `gno.land/r/REPLACE_ADDR/quotes`
- **State-mutating tx:** `AddQuote(text string)` — a gno 0.9 crossing function.
- **View:** `Render(path string)` — Markdown; a blockquote featured pick chosen
  by `ChainHeight() % len(quotes)`, followed by the full list with author + id.

## Example calls

Add a quote (MsgCall dispatches to the crossing function; you do not write
`cross(cur)` on the command line — the chain supplies it):

```sh
gnokey maketx call \
  -pkgpath "gno.land/r/REPLACE_ADDR/quotes" \
  -func AddQuote \
  -args "Luck is what happens when preparation meets opportunity." \
  -gas-fee 1000000ugnot -gas-wanted 2000000 \
  -broadcast -chainid test13 -remote <rpc> <key>
```

View the rendered board in gnoweb:

```
https://gno.land/r/REPLACE_ADDR/quotes
```

Or query the render output directly:

```sh
gnokey query "vm/qrender" -data "gno.land/r/REPLACE_ADDR/quotes:" -remote <rpc>
```
