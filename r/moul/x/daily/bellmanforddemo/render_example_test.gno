package bellmanforddemo

// ExampleRender pins the realm Render output as a testable example.
//
// The block below is copied verbatim from what gno printed, never hand
// typed: every distance, every state and the cycle itself is computed by the
// library under test, so a change in the search shows up here as a diff
// rather than as prose.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Bellman-Ford
	//
	// Cheapest routes across a graph whose arcs may cost less than nothing, demoing the [`p/moul/x/daily/bellmanford`](/p/moul/x/daily/bellmanford/v0) library.
	//
	// ## A fee table with a rebate in it
	//
	// 7 nodes, 8 one-way arcs, priced from `gate`. One of them is negative: `depot` pays 3 back for sending on.
	//
	// | from | to | cost |
	// | --- | --- | --- |
	// | gate | hubA | 7 |
	// | gate | hubB | 2 |
	// | gate | market | 4 |
	// | hubB | hubA | 1 |
	// | hubA | depot | 2 |
	// | hubB | depot | 4 |
	// | depot | market | -3 |
	// | market | vault | 2 |
	//
	// `cold` is in the graph with no arcs at all.
	//
	// ## Cheapest route to each node
	//
	// | node | state | distance | arrives via | route |
	// | --- | --- | --- | --- | --- |
	// | gate | settled | 0 | source | gate |
	// | hubA | settled | 3 | hubB | gate -> hubB -> hubA |
	// | hubB | settled | 2 | gate | gate -> hubB |
	// | market | settled | 2 | depot | gate -> hubB -> hubA -> depot -> market |
	// | depot | settled | 5 | hubA | gate -> hubB -> hubA -> depot |
	// | vault | settled | 4 | market | gate -> hubB -> hubA -> depot -> market -> vault |
	// | cold | unreached | unreached |  |  |
	//
	// The two rows worth reading twice are `market` and `vault`. `market` sits one arc from the source at a cost of 4, and the cheapest way to it is the four-arc detour through the rebate, at 2. A search that settles a node at its best known cost and never looks at it again would have stopped at 4, because `depot` is only priced later, and `vault` would have inherited the mistake.
	//
	// ## What the rebate is worth
	//
	// The same network with that one arc priced at +3 instead, so the detour is a detour and nothing else.
	//
	// | node | with the rebate | without it |
	// | --- | --- | --- |
	// | gate | 0 | 0 |
	// | hubA | 3 | 3 |
	// | hubB | 2 | 2 |
	// | market | 2 | 4 |
	// | depot | 5 | 5 |
	// | vault | 4 | 6 |
	// | cold | unreached | unreached |
	//
	// One arc, two answers changed. That is the whole reason to pay O(V*E) instead of O((V+E) log V).
	//
	// ## How many passes it took
	//
	// The algorithm relaxes every arc, over and over, until a pass changes nothing. A shortest path visits each node at most once, so it is at most V-1 arcs long, and one pass extends every known route by at least one arc.
	//
	// | figure | value | meaning |
	// | --- | --- | --- |
	// | nodes | 7 | V |
	// | arcs | 8 | E |
	// | bound | 6 | V-1 passes, the worst case |
	// | passes made | 2 | it stopped as soon as a pass changed nothing |
	// | improvements | 7 | arcs that actually lowered a distance |
	//
	// The passes figure is decided by the order the arcs were added in, not by the graph, so it is the number to watch when gas matters.
	//
	// ## When there is no cheapest route at all
	//
	// Change one price and the ring `loopA -> loopB -> loopC` pays more back than it costs.
	//
	// | from | to | cost |
	// | --- | --- | --- |
	// | mint | safe | 5 |
	// | mint | loopA | 1 |
	// | loopA | loopB | 2 |
	// | loopB | loopC | -4 |
	// | loopC | loopA | 1 |
	// | loopC | sink | 3 |
	//
	// Going round it once saves 1, so going round it twice saves twice as much, and asking for the cheapest route to anything it reaches has no answer. The run says so instead of returning the total after an arbitrary number of turns:
	//
	// | node | state | distance | route |
	// | --- | --- | --- | --- |
	// | mint | settled | 0 | mint |
	// | safe | settled | 5 | mint -> safe |
	// | loopA | unbounded | unbounded |  |
	// | loopB | unbounded | unbounded |  |
	// | loopC | unbounded | unbounded |  |
	// | sink | unbounded | unbounded |  |
	//
	// | what the run found | value |
	// | --- | --- |
	// | the cycle | loopC -> loopA -> loopB -> loopC |
	// | one turn costs | -1 |
	// | nodes it poisons | loopA, loopB, loopC, sink |
	//
	// `mint` and `safe` keep real distances: the cycle cannot reach them, so nothing it does changes what they are worth. Reporting the blast radius rather than failing the whole query is the difference between a fee table a realm can act on and one it has to throw away.
	//
	// ## What it will not do
	//
	// | limit | value | why |
	// | --- | --- | --- |
	// | `MaxNodes` | 512 | V bounds the pass count |
	// | `MaxEdges` | 4000 | E bounds the work per pass |
	// | `MaxWeight` | 1099511627776 | V times this is the largest total, well inside an int |
	// | unknown source | panics | a typo must not read as "nothing is reachable" |
	// | negative cycle | reported | it is an answer, not an error |
	//
	// There is no unreachable sentinel on `Dist`, and there cannot be: a negative total is a legitimate answer here, so every value it could reserve is one a real route might have. Ask `State` when the reason matters.
}
