# `gno.land/r/moul/toolbox/v0`

**A home for small utilities on gno.land.** One page listing every tool; each tool is its own
realm at `r/moul/toolbox/<slug>`.

A tool composes contracts that are already on chain and renders the answer, so you open a page
instead of composing a query. The toolbox adds the view, not the data.

```
/r/moul/toolbox/v0                  the directory
/r/moul/toolbox/v0?tag=identity     the directory, filtered to one tag
/r/moul/toolbox/v0:usernames        one tool
```

## The catalog is compiled in, and that is the interesting part

The obvious design is the opposite one: each tool calls `Register` on this realm from its own
init, and the directory assembles itself. That design is unavailable here, and the reason is
not a preference.

`private = true` buys redeploy-in-place at the same path and costs the ability to be imported:
the type checker refuses any realm importing a private one (`ImportPrivateError`). A private
hub therefore cannot be imported by its tools, and a hub that accepts registration has to be
public. **A public realm can never be redeployed at its own path**, so a public hub would be
frozen at v0 and the first bug in it would move the directory's URL.

A stable URL is the whole point of a directory, so the trade goes the other way: everything
here is private and redeployable, and adding a tool is one entry in `tools` plus a redeploy.
The catalog is rebuilt from source every time, so the redeploy wipe costs nothing. There is no
state to lose.

[`p/moul/toolbox`](https://gno.land/p/moul/toolbox/v0)'s `Catalog` stays mutable for whoever
wants the other trade.

## Adding a tool

One entry in `tools`, then redeploy. `buildCatalog` panics at deploy, not at read, if the slug
and the path disagree, so a copy-pasted entry that kept the wrong path fails the publish rather
than shipping a dead link.

## The read API

Flat strings, because a nested value inside a persisted object prints as an opaque `ref(...)`
over `vm/qeval`:

```sh
gnokey query vm/qeval -remote https://rpc.gno.land \
  -data 'gno.land/r/moul/toolbox/v0.Slugs()'
gnokey query vm/qeval -remote https://rpc.gno.land \
  -data 'gno.land/r/moul/toolbox/v0.PathOf("usernames")'
```
