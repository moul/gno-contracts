# `gno.land/r/moul/x/daily/dijkstrademo/v0`

**A gnoweb page for the shortest-path search in [`p/moul/x/daily/dijkstra`](/p/moul/x/daily/dijkstra/v0)**: the cheapest route to every node, the order the search settles them in, and the tie-break that makes both reproducible.

```go
import "gno.land/r/moul/x/daily/dijkstrademo/v0"

dijkstrademo.Render("")   // → the whole page, from fixed inputs
```

The library's own tests prove it computes the right distances. They cannot show what the algorithm is doing, and the thing most worth seeing is the settle order: always the closest node still outstanding, never the next one along an arc. That is the entire difference from a breadth-first walk, and it is why a cheap long way round beats an expensive short one.

**Every figure on the page is computed, never written down.** The seven-arc network and the three-spoke fanout are declared at the top of the realm and nothing else feeds them, so `ExampleRender` pins the output byte for byte: change the search and the diff lands in the test rather than in the prose.

Three behaviours worth knowing before you read it:

- **The worked example is built so the obvious answers are wrong twice.** `east` has a direct arc costing 4 and the answer is 3 through `north`; `port` is first offered at 9 and ends at 8, two settlements later. A demo whose greedy first guess happened to be right would teach nothing.
- **The tie table is the consensus argument, not decoration.** It builds the same hub-and-spoke graph twice with the spokes declared in opposite orders, and shows the settle order following the declaration both times. That is the property a realm depends on: map iteration order here would mean two validators rendering two different pages.
- **`quarry` is in the graph with no arcs.** Unreachable is an answer the page shows, not an error it hides, because a realm reading `Dist` has to handle it either way.

No search logic of its own, no chain state, no caller input: stateless and deterministic, which is what makes it pinnable.
