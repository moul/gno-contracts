# Counter Club

> ⚠️ **Experimental — generated with no human supervision.** This realm was
> produced automatically by an MCP-driven agent to exercise the gno MCP server
> and tooling, and to generate test content for gno compilers, linters and
> formatters. **Not audited. Not for production.** Full context & folder README:
> [r/moul/daily/x](https://github.com/moul/gno-contracts/blob/main/r/moul/daily/x/README.md)

---


A single shared integer counter that anyone on the chain can nudge. Every call
to `Inc`, `Dec`, or `Reset` mutates the global value and appends a record to a
rolling log of the last 20 changes (caller address, delta, new value, block
height). The realm's `Render` shows the current value big, the total number of
changes ever made, and a table of the recent history.

**Realm path:** `gno.land/r/REPLACE_ADDR/counter`

## Example calls

```sh
# Increment the shared counter
gnokey maketx call -pkgpath "gno.land/r/REPLACE_ADDR/counter" \
  -func Inc -gas-fee 1000000ugnot -gas-wanted 2000000 -broadcast -chainid test13 KEY

# Decrement it
gnokey maketx call -pkgpath "gno.land/r/REPLACE_ADDR/counter" \
  -func Dec -gas-fee 1000000ugnot -gas-wanted 2000000 -broadcast -chainid test13 KEY

# Reset back to zero
gnokey maketx call -pkgpath "gno.land/r/REPLACE_ADDR/counter" \
  -func Reset -gas-fee 1000000ugnot -gas-wanted 2000000 -broadcast -chainid test13 KEY
```

View the current value and history by rendering the realm in a gno.land
explorer or with `gnokey query vm/qrender --data "gno.land/r/REPLACE_ADDR/counter:"`.
