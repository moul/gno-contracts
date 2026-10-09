# `gno.land/p/moul/toolbox/v0`

**The directory model behind [r/moul/toolbox](https://gno.land/r/moul/toolbox)**: `Tool`,
`Catalog`, `BasePath`, `SlugOf`, `NewQuery`, `Index`, `Card`, `Nav`.

```go
import "gno.land/p/moul/toolbox/v0"

var c toolbox.Catalog
c.Set(toolbox.Tool{
    Slug:  "usernames",
    Path:  "gno.land/r/moul/toolbox/usernames",
    Title: "Usernames",
    Desc:  "Resolve a username to an address, or an address to a username.",
    Tags:  []string{"identity", "read"},
})

toolbox.Index(c.List())                       // → the markdown table of the directory
toolbox.SlugOf("gno.land/r/moul/toolbox",
               "gno.land/r/moul/toolbox/usernames") // → "usernames"
toolbox.NewQuery("lookup").Field("q", "username or g1 address").String()
```

A toolbox is a hub realm listing tools, each tool a realm of its own one level below it. The
hub is `private = true`, which costs it the ability to be imported at all: the type checker
refuses any realm importing a private one. So the hub and its tools cannot share a single line
of code by importing each other, and everything they must agree about lives here instead.

**Nesting is checked on the base path, not the full one.**
[`p/moul/nestedpkg`](https://gno.land/p/moul/nestedpkg/v0) decides "is the caller below me" by
prefixing one package path with the other. That is exactly right once neither side carries a
version, which is the case for a private hub, and it breaks the moment either does:
`gno.land/r/moul/toolbox/usernames/v0` does not begin with `gno.land/r/moul/toolbox/v0`.
`BasePath` strips a trailing `/vN` so the comparison is about the family rather than the
version, and `IsUnder` and `SlugOf` are built on it: a hub and a tool may each be versioned or
not, independently, and all four combinations answer the same. A sibling whose name merely
starts with the hub's (`toolboxtwo`) is not under it, because the comparison is against the
base plus a slash.

Five behaviours worth knowing before you use it:

- **`Tool` is strings all the way down.** A tool that registers itself into a public hub hands
  these values across a realm boundary, and a struct the caller allocated stays the caller's
  object: persisting it panics with `cannot persist object from the private realm`. Scalars are
  copied, so the hub owns what it stores whichever side built the entry.
- **`Catalog` is a slug-keyed B+ tree (fanout 32), not a sorted slice.** The slice is cheaper to
  *read* at this size: at n = 100 one cold operation costs 92,571 gas against a fanout-128
  tree's 230,754 (`gnobench`, gno master `1fc4c140e`, 2026-09-29). It is still wrong. A slice is
  one persisted object, so every write rewrites all of it, O(n) per transaction and O(n^2) over n
  of them, which is free for a compiled-in catalog and is the whole bill for a hub that accepts
  registration. Removing is worse: shortening a slice in place keeps the peak allocation charged
  and refunds no deposit. Fanout 32 rather than 128 because a tool can be unregistered and wide
  nodes lose most on removal. Slug order comes free from the tree rather than from a hand-rolled
  binary search.
- **A `Catalog` is a handle.** Copying one shares the directory, the way copying a map does, and
  a write through either copy is seen through both. A copy of a zero value that was never
  written is a separate empty catalog.
- **`Catalog` never aliases a `Tool.Tags` slice**, in either direction: it copies on the way in
  so the caller of `Set` keeps no handle on stored state, and on the way out so
  `c.List()[0].Tags[0] = "x"` cannot reach the directory.
- **`NewQuery` builds a read, never a write.** It emits gnoweb's `<gno-form path="...">`, whose
  submission redirects to one of the realm's own `Render` paths with the fields as query
  parameters. Nothing is signed and no transaction is built. A form that calls a function is a
  different element (`<gno-form exec="Fn">`) and is deliberately not this one with a flag.

Every string is escaped exactly once, with the helper for the slot it lands in, and the
escapers are not idempotent: `md.Link` and `md.InlineCode` sanitize their own arguments, so
`Index` builds its title link by hand (`ui.Cell` for link text inside a cell, `md.EscapeURL`
for the href) rather than wrapping twice. Attribute values go through an
HTML escaper: gnoweb parses forms with a real tokenizer, so an unescaped quote ends the
attribute and whatever follows becomes further attributes of the same tag.
