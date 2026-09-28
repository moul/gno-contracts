# `gno.land/p/moul/reactions/v0`

The engine behind an embeddable reaction block: pages, tallies, a closed emoji
palette, and the markdown that shows them. No realm state, no chain reads, no
authority decisions. The realm on top owns all three.

Live realm: [`gno.land/r/moul/reactions/v0`](https://github.com/moul/gno-contracts/tree/main/r/moul/reactions).

## The model

A `Board` maps a **page key** to a `Page`. A page holds exactly three things:

| | |
|---|---|
| a count per palette key | what the strip shows |
| the **current** reaction of each address | so a tally counts addresses and not clicks, and a reader can change their mind or take it back |
| the last reaction | which key, from whom, at what height |

There is no text field anywhere. That is what makes the whole thing runnable
with no moderation: reactions come from a closed set of six, so there is nothing
to take down.

```go
b := reactions.NewBoard()
b.React("gno.land/r/moul/home", caller, reactions.KeyFire, height) // false if rejected
b.Unreact("gno.land/r/moul/home", caller)                          // false if there was none

p := b.Page("gno.land/r/moul/home") // nil when untouched, and nil is safe to use
p.Count(reactions.KeyFire)          // 1
p.Total()                           // addresses reacting, not clicks
p.Of(caller)                        // "fire", or "" for none
key, who, height := p.Last()

md := reactions.Block(realmPath, page, p) // the whole widget
```

Every `Page` read is nil-safe and answers as if the page were empty, so a host
realm renders the block without ever checking whether the page exists.

## Three decisions worth knowing before you use it

**A reaction key is an ASCII name, not a glyph.** `"up"`, not `👍`. A name
survives a URL query parameter, an avl key and a markdown escaper with no
encoding question anywhere, and the palette can change a glyph without
rewriting stored state. `Emoji(key)` is the presentation half.

**No glyph in the palette uses U+FE0F or a zero-width joiner.** The link title
goes through `ui.Inline`, which strips exactly those, so a glyph needing a
variation selector would come out the other side as its monochrome form. ❤️ is
the casualty; `heart` is 💜, a codepoint that is colour on its own. Pinned by
`TestEmojiSurviveTheEscaper`.

**`Unreact` does not rewind the last-reaction line.** It records an event that
happened, and recomputing it would mean walking every address on the page. The
line under the block says what happened here last, which is a different question
from what is currently counted.

## Page keys

A page key is a package path, and `ValidPage` is what bounds this package's
exposure: at least one `/`, no empty element, and only lowercase ASCII letters,
digits, `.`, `-`, `_`, `:` and `/`, up to `MaxPageLen` bytes. That excludes every
character a markdown escaper exists for, plus every byte above ASCII, so a
stored key can never be a bidi run, a zero-width joiner or an image.

`:` is in the set so a host realm can key one block per article on the path it
already serves: `gno.land/r/you/blog:hello-world`.

This package only ever puts a key in a URL. A realm that shows the key **as
text** escapes it there; `ValidPage` and `ui.Inline` protect against different
mistakes.

## Not to be confused with

[`r/moul/x/daily/reactions`](https://github.com/moul/gno-contracts/tree/main/r/moul/x/daily/reactions)
is an older, unrelated experiment: a single self-contained board with its own
"topics", no embedding, and no way for a reader to change or remove a reaction.
Nothing is shared between the two.
