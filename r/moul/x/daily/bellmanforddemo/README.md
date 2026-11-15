# `gno.land/r/moul/x/daily/bellmanforddemo/v0`

**A gnoweb page for the shortest-path search in [`p/moul/x/daily/bellmanford`](/p/moul/x/daily/bellmanford/v0)**: a fee table with a rebate in it, what that one arc is worth, and what the run says when no cheapest route exists at all.

```go
import "gno.land/r/moul/x/daily/bellmanforddemo/v0"

bellmanforddemo.Render("")   // → the whole page, from fixed inputs
```

The library's own tests prove it computes the right distances. They cannot show *why* paying `O(V*E)` is worth it, and that is the thing most worth seeing: the page runs the same eight-arc network twice, once with the rebate and once with that single arc priced the other way, side by side. Two answers change. Everything else is identical.

**Every figure on the page is computed, never written down.** The two networks are declared at the top of the realm and nothing else feeds them, so `ExampleRender` pins the output line for line: change the search and the diff lands in the test rather than in the prose.

Three things the page is built to show:

- **The obvious route is wrong, and the reason is late.** `market` sits one arc from the source at a cost of 4, and the cheapest way to it is a four-arc detour at 2, because `depot` pays 3 back and `depot` is only priced two settlements later. A search that never revisits a settled node would have stopped at 4 and handed the mistake on to `vault`.
- **The negative cycle section is the honest-failure case.** One price change turns `loopA -> loopB -> loopC` into a ring that pays 1 per turn, and the page shows the ring, what a turn costs, and exactly which nodes it poisons. `mint` and `safe` keep their real distances throughout: the cycle cannot reach them.
- **`cold` is in the graph with no arcs.** Unreachable is an answer the page prints, not an error it hides, and it prints as a *state* rather than as a blank cell, because a blank would read like zero and zero is a real distance here.

No search logic of its own, no chain state, no caller input: stateless and deterministic, which is what makes it pinnable.
