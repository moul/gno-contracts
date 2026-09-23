# `r/moul/x/allinone`

Demo realms that exist to **combine** packages, not to explain one.

Almost every `p/moul/*` package already has a demo realm showing it alone.
What none of those can show is what the packages look like used together, which
is the only form a real realm ever meets them in. These fill that gap.

## The rules

1. **At least five packages**, and every one of them visible in the output. A
   package imported and not used is not a combination, it is a longer import
   block.
2. **The combination is the point.** A demo should answer a question that no
   single-package demo can: how two algorithms disagree, what a realm's whole
   toolbelt looks like wired up at once.
3. **State is disposable.** Every realm here is `private = true` and expected to
   be redeployed whenever one of the packages it shows off changes. A redeploy
   re-runs `init()` and wipes every package-level variable, so nothing lives
   here that anyone would miss. That is what makes these the safe dogfood
   target: the realms with real accumulated history are not.
4. **Bounded.** Anything a caller can append to has a ceiling in the type, and
   anything a caller can put in a URL is length-checked before it reaches an
   algorithm. Storage is paid for and never refunded, and a render is served to
   whoever asks.
5. **Escape everything a caller typed.** `ui.Inline` in prose, `ui.Cell` in a
   table. These realms take input from URLs and from anyone, so they are the
   worst place to skip it and the best place to demonstrate it.

## The demos

| realm | packages | what the combination shows |
|---|---|---|
| [`devtools`](./devtools) | 8 | the whole toolbelt wired into one realm: notice block, pause guard, explorer links, debug panel, escaped input, bounded storage. The file to copy when starting a realm. |
| [`textlab`](./textlab) | 8 | every string algorithm over one input, so they can be compared. soundex and levenshtein measure different things and disagree in both directions. |

## Adding one

Pick packages that have a reason to meet. Write the realm, give it an
`ExampleRender`, and put the claim it demonstrates in a test rather than in
prose: `textlab` shipped a package doc asserting a "textbook" result that turned
out to be backwards, and a test caught it. The numbers on those pages are now
pinned by `TestTheDisagreement`, so the page cannot quietly start lying.
