# `gno.land/p/moul/toolbox/v0`

**The directory model behind [r/moul/toolbox](https://gno.land/r/moul/toolbox/v0)**: `Tool`,
`Catalog`, `BasePath`, `SlugOf`, `NewQuery`, `Index`, `Card`, `Nav`.

```go
import "gno.land/p/moul/toolbox/v0"

var c toolbox.Catalog
c.Set(toolbox.Tool{
    Slug:  "usernames",
    Path:  "gno.land/r/moul/toolbox/usernames/v0",
    Title: "Usernames",
    Desc:  "Resolve a username to an address, or an address to a username.",
    Tags:  []string{"identity", "read"},
})

toolbox.Index(c.List())                       // → the markdown table of the directory
toolbox.SlugOf("gno.land/r/moul/toolbox/v0",
               "gno.land/r/moul/toolbox/usernames/v0") // → "usernames"
toolbox.NewQuery("lookup").Field("q", "username or g1 address").String()
```

A toolbox is a hub realm listing tools, each tool a realm of its own one level below it. The
hub is `private = true`, which costs it the ability to be imported at all: the type checker
refuses any realm importing a private one. So the hub and its tools cannot share a single line
of code by importing each other, and everything they must agree about lives here instead.

**Versioned paths break the obvious nesting check, deliberately not papered over.**
[`p/moul/nestedpkg`](https://gno.land/p/moul/nestedpkg/v0) decides "is the caller below me" by
prefixing one package path with the other, which is right for unversioned paths and wrong for
every path in this repository: `gno.land/r/moul/toolbox/usernames/v0` does not begin with
`gno.land/r/moul/toolbox/v0`. `BasePath` strips the trailing `/vN` so the comparison is about
the family rather than the version, and `IsUnder` and `SlugOf` are built on it. A sibling whose
name merely starts with the hub's (`toolboxtwo`) is not under it, because the comparison is
against the base plus a slash.

Four behaviours worth knowing before you use it:

- **`Tool` is strings all the way down.** A tool that registers itself into a public hub hands
  these values across a realm boundary, and a struct the caller allocated stays the caller's
  object: persisting it panics with `cannot persist object from the private realm`. Scalars are
  copied, so the hub owns what it stores whichever side built the entry.
- **`Catalog` is a sorted slice, not a tree.** A directory is tens of entries read far more
  often than written; at n = 100 a sorted slice costs 92,571 gas for one cold operation against
  `avl`'s 164,812 (`gnobench`, gno master `1fc4c140e`, 2026-09-29), in one persisted object
  rather than one per node. Sorted by slug rather than by insertion, because a `Render` that
  reshuffles between two identical calls is a bug.
- **`Catalog.List` returns a copy.** A caller rewriting an element of the returned slice cannot
  reach the directory through it.
- **`NewQuery` builds a read, never a write.** It emits gnoweb's `<gno-form path="...">`, whose
  submission redirects to one of the realm's own `Render` paths with the fields as query
  parameters. Nothing is signed and no transaction is built. A form that calls a function is a
  different element (`<gno-form exec="Fn">`) and is deliberately not this one with a flag.

Every cell `Index` renders goes through `ui.Cell` first, and attribute values go through an
HTML escaper: gnoweb parses forms with a real tokenizer, so an unescaped quote ends the
attribute and whatever follows becomes further attributes of the same tag.
