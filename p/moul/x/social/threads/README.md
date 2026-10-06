# `gno.land/p/moul/x/social/threads/v0`

**The engine behind an embeddable discussion block**, keyed on the page it is
shown under rather than on the realm that stores it: `NewBoard`, `Post`,
`Reply`, `Pin`, `List`, `Recent`, `Block`.

```go
b := threads.NewBoard()
id, _ := b.Post("gno.land/r/moul/home", author, "worth discussing", height)
isNew, _ := b.Reply(id, replier, "it is", height)   // isNew is the mint signal
b.Pin(id, height+1000)                              // placement, bought elsewhere
threads.Block(realmPath, page, b.List(page, height, 5), b.PageLen(page), height)
```

**A forum is a destination and has to earn its traffic before anybody writes
the first post. A block does not.** It is dropped into pages that already have
readers, and the discussion attaches to the object it is about: a realm page, a
proposal, an address. One realm holds every thread, every host realm ships the
same two lines, and no host realm stores anything. That is the shape the web
settled on for comments in 2010, and the same one
[`p/moul/reactions`](https://github.com/moul/gno-contracts/tree/main/p/moul/reactions)
uses for the tally. The two are deliberate neighbours and share a page key
format: reactions are a closed palette and need no moderation, text needs some,
so a realm can take the cheap one alone.

**`Reply` reports whether the replier was new to that thread**, and that boolean
is the whole reason the package keeps a replier set. A realm paying an author
for attention wants distinct people, not distinct messages, and a thread's own
author replying to themselves is never new. The mint rule then has exactly one
signal and exactly one call site.

**`List` is a partition, not a sort**: pinned first, then the rest, both newest
first. No comparator, no tie to break, and two identical calls always produce
the same page, which is what a `Render` needs. A pin is an absolute height, so
it expires on its own and nothing has to sweep it. `Pin` refuses to move a pin
backwards, so a cheap pin cannot cut an expensive one short; what a pin costs is
the realm's decision, not this package's.

**A body is free text and therefore attacker-controlled markdown.** `ValidBody`
bounds it and refuses control characters, which is a different protection from
escaping and not a substitute for it: everything rendered here goes through
`ui.Inline` or `ui.Cell`, and so must any realm that renders a body itself. Note
`Block` truncates with `ui.ShortN` and then hands the result to `md.Link`, which
escapes: `ui.Excerpt` there would escape twice and render the backslashes.

A page key is a package path, validated by `ValidPage` to the same rule
`p/moul/reactions` uses, so a realm embedding both blocks passes one key to both.

**Live realm:** [`r/moul/x/social/threads`](https://github.com/moul/gno-contracts/tree/main/r/moul/x/social/threads)
· render it at [`/r/moul/x/social/threads/v0`](https://gno.land/r/moul/x/social/threads/v0).
