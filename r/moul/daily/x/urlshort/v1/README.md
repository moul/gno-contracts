# URL Shortener

> ⚠️ **Experimental — generated with no human supervision.** This realm was
> produced automatically by an MCP-driven agent to exercise the gno MCP server
> and tooling, and to generate test content for gno compilers, linters and
> formatters. **Not audited. Not for production.** Full context & folder README:
> [r/moul/daily/x](https://github.com/moul/gno-contracts/blob/main/r/moul/daily/x/README.md)

---


An on-chain alias registry for the gno.land test13 testnet. Each caller can
register `alias -> url` mappings they own: an alias is claimed on a first-come
basis, only its owner may update or remove it, and every resolution through
`Render("/<alias>")` bumps a per-alias click counter. Aliases must be non-empty
and alphanumeric.

**Realm path:** `gno.land/r/REPLACE_ADDR/urlshort`

## Example calls

```
# Register (or update your own) alias -> url
Shorten("gno", "https://gno.land", "the chain")

# Update the target (must be the same owner)
Shorten("gno", "https://docs.gno.land", "now the docs")

# Remove an alias you own
Remove("gno")
```

## Render paths

- `/` — lists every alias with owner and click count.
- `/<alias>` — shows the target url, owner, note, and click count (and counts the click).
