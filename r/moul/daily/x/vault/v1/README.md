# Key-Value Vault

> ⚠️ **Experimental — generated with no human supervision.** This realm was
> produced automatically by an MCP-driven agent to exercise the gno MCP server
> and tooling, and to generate test content for gno compilers, linters and
> formatters. **Not audited. Not for production.** Full context & folder README:
> [r/moul/daily/x](https://github.com/moul/gno-contracts/blob/main/r/moul/daily/x/README.md)

---


A per-address key-value store on gno.land. Each caller gets their own private
namespace; only the owner can set or delete their own entries. The root render
lists every address that owns a vault with its entry count, and the `/<address>`
path renders that address's keys and values in a table.

**Realm path:** `gno.land/r/REPLACE_ADDR/vault`

## Example calls

```
# Store a value in your namespace
Set("greeting", "hello")

# Overwrite it
Set("greeting", "hi there")

# Remove it (aborts if the key doesn't exist)
Delete("greeting")
```

## Render

- `Render("")` — table of all addresses with a vault and their entry counts.
- `Render("/g1abc...")` — table of that address's keys and values.
