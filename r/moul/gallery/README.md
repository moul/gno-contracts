# `gno.land/r/moul/gallery/v0`

A curated index of art on gno.land, in whichever form the reader can actually
consume.

**It stores no art.** Every piece lives in somebody's realm; this one renders
the ones it can import and points at the ones it cannot. There is no
package-level state anywhere in it, so there is nothing for a redeploy to wipe
and nothing it pays storage for.

## Rendered, or linked, and it says which

| | |
|---|---|
| **rendered here** | the source realm is public, so the gallery imports it and calls it live: `gnoface`, `millipede`, `sapin` |
| **linked** | the source cannot be imported, so the gallery points at it and says so rather than showing an empty box |

`asciiart` is the honest case: it declares `private = true`, which means no realm
may ever import it. That is a constraint of the chain, not an omission here, and
the piece page says exactly that.

## The target is a parameter

Every page answers to `?fmt=txt` as well as the default markdown.

The text target is **not markdown with the characters deleted**. It is a
different document built from the same content:

1. A link prints its text inline and collects the URL into a numbered footnote
   at the end. Never `[text](url)`, which is the single worst thing markdown
   does to a terminal reader.
2. A heading is underlined (`=` for H1, `-` for H2), not prefixed with `#`.
3. A table gets columns padded to their widest cell, under a rule. An unpadded
   pipe table is the other thing no amount of character-stripping fixes.
4. Art is emitted **verbatim**: never wrapped, never escaped, never fenced. A
   consumer that asked for text asked for the picture as it is.
5. Prose wraps at 72 runes. A word longer than that is left alone, because a
   realm path is worse broken than wide.

```
/r/moul/gallery:?fmt=txt                 the index, pipeable
/r/moul/gallery:piece/millipede?fmt=txt  one piece, art and all
```

`?fmt=ansi` is deliberately **absent**. Colour cannot reach gnoweb:
`p/nt/markdown/sanitize` strips control bytes and raw ESC is garbage in HTML, so
a realm offering it would hand every web reader a page of escape bytes. Terminal
colour is `p/moul/art`'s `Canvas.ANSI`, for a consumer that asked for it over
something other than gnoweb.

## Where the text renderer lives, and why it is here

`text.gno` holds `doc`, a small plain-text document builder. It is a
**prototype**, deliberately in this realm rather than in a `p/` package.

Porting one realm is not enough to know what a shared document model should be;
porting the fifth will be. What it already pins is the list of five rules above,
which is the part that was actually unknown. When a second realm needs it, it
graduates to `p/moul/doc` and this file becomes an import.

## Adding a piece

`catalog()` in `catalog.gno`, one struct literal. Set `Draw` to a closure over
the source realm's function when the realm is public and vendored; leave it nil
and the gallery will link the piece and say why it is not rendered.

The catalog is built per call rather than held in a package-level var: a func
value is not something to persist, and a realm that stores nothing should not be
paying storage for its own index.
