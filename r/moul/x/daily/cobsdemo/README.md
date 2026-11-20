# `gno.land/r/moul/x/daily/cobsdemo/v0`

**A gnoweb demo of [`p/moul/x/daily/cobs`](/p/moul/x/daily/cobs/v0)**: four tables, no state,
no codec logic of its own.

```
/r/moul/x/daily/cobsdemo/v0         the frames, the overhead, the packing, the refusals
/r/moul/x/daily/cobsdemo/v0:/hello  frame one string and show the bytes
```

The first table prints a frame byte for byte, because the group code is the whole idea and it
is faster to see once than to read twice. The second is the one worth coming for: it puts the
overhead of an all-zero payload next to a payload with no zeros and next to what escaping
would have cost, and the order is the opposite of what escaping teaches. The third packs five
records, one of them empty and two with zeros inside, into one string and gets them back out.
The fourth feeds the decoder four frames it refuses and prints the error, because the
canonical form rule is the library's one real design decision and a demo that only showed
successes would hide it.

**Every figure on the page is measured, not written down.** The overhead column calls
`Encode` on the spot, the packed length is `len(Pack(records))`, and the refusal column prints
whatever error `Decode` actually returned. Breaking the library's canonical form check turns
the last row into a line saying the table is wrong, and `TestRenderIndexStatesTheOverheadItMeasures`
fails on it: a demo with its own hardcoded answers is a page that keeps agreeing after the
library stops.

**Fixed inputs, never chain state, deliberately.** Every payload rendered here is a package
level variable. Output that moved with the block height could not be pinned by
`ExampleRender`, and an unpinned `Render` is how a realm ships a page nobody ever read.

The path argument is caller-supplied, so it goes through `md.InlineCode` before it is
rendered, and not through `ui.Cell`: it sits inside a code span, a cell escaper backslashes a
backtick, and a backslash does not close a backtick inside a span. Only a fence wider than
anything in the argument does, which is what `md.InlineCode` picks. A realm's `Render` can
never be fixed once the path is live, and an unescaped argument is how a caller rewrites the
page around it.

The argument page also decodes the frame it just printed and says so, rather than printing an
encoding and leaving the round trip as a claim in the README.

`parseArg` takes the one routing slash off and nothing else: it does not cut at a later slash
and it does not trim. A page that offers to frame what the caller typed either frames that
string or says it refused it, and never quietly substitutes a shorter or tidier one.
