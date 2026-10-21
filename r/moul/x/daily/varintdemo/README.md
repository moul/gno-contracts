# `gno.land/r/moul/x/daily/varintdemo/v0`

**A gnoweb demo of [`p/moul/x/daily/varint`](/p/moul/x/daily/varint/v0)**: three tables, no
state, no codec logic of its own.

```
/r/moul/x/daily/varintdemo/v0        the vector tables and the refusals
/r/moul/x/daily/varintdemo/v0:/-300  encode one integer, both ways
```

The first table walks the unsigned group boundaries, so you can see the length step at every
power of 128 instead of taking it on trust. The second puts each signed value next to its
zigzag, which is the only way the one-byte `-1` stops looking like a trick. The third feeds
the decoder four inputs it refuses and prints the error it returns, because the canonical
form rule is the library's one real design decision and a demo that only showed successes
would hide it.

**Fixed inputs, never chain state, deliberately.** Every value rendered here is a package
level constant. Output that moved with the block height could not be pinned by
`ExampleRender`, and an unpinned `Render` is how a realm ships a page nobody ever read.

The path argument is caller-supplied, so it goes through `ui.Cell` before it is rendered: a
realm's `Render` can never be fixed once the path is live, and an unescaped argument is how a
caller rewrites the page around it. `ExampleRender_one` pins the escaped form.
