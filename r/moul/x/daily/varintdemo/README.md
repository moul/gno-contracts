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

The path argument is caller-supplied, so it goes through `md.InlineCode` before it is
rendered, and not through `ui.Cell`: it sits inside a code span, a cell escaper backslashes a
backtick, and a backslash does not close a backtick inside a span. Only a fence wider than
anything in the argument does, which is what `md.InlineCode` picks. A realm's `Render` can
never be fixed once the path is live, and an unescaped argument is how a caller rewrites the
page around it.

`parseArg` takes the one routing slash off and nothing else: it does not cut at a later slash
and it does not trim. A page that offers to encode what the caller typed either encodes that
string or says it refused it, and never quietly substitutes a shorter or tidier one.
