package dijkstrademo

// ExampleRender pins the realm Render output as a testable example.
//
// The block below is copied verbatim from what gno printed, never hand typed:
// every distance and every ordering in it is computed by the library under
// test, so a change in the search shows up here as a diff rather than as
// prose.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Dijkstra
	//
	// The cheapest route from one node to every other node of a weighted graph, demoing the [`p/moul/x/daily/dijkstra`](/p/moul/x/daily/dijkstra/v0) library.
	//
	// ## The network
	//
	// Arcs are one-way. 7 nodes, 7 arcs, searched from `depot`.
	//
	// | from | to | cost |
	// | --- | --- | --- |
	// | depot | north | 2 |
	// | depot | east | 4 |
	// | north | east | 1 |
	// | north | ridge | 3 |
	// | east | port | 6 |
	// | ridge | port | 3 |
	// | port | beacon | 2 |
	//
	// `quarry` is in the graph with no arcs at all.
	//
	// ## Cheapest route to each node
	//
	// | node | distance | arrives via | route |
	// | --- | --- | --- | --- |
	// | depot | 0 | source | depot |
	// | north | 2 | depot | depot -> north |
	// | east | 3 | north | depot -> north -> east |
	// | ridge | 5 | north | depot -> north -> ridge |
	// | port | 8 | ridge | depot -> north -> ridge -> port |
	// | beacon | 10 | port | depot -> north -> ridge -> port -> beacon |
	// | quarry | unreachable |  |  |
	//
	// Two of those rows are the point of the algorithm. `east` is reachable directly for 4, and the answer is 3, through `north`. `port` is first offered at 9 by `east`, and ends at 8 through `ridge`, which the search only discovers two settlements later.
	//
	// ## The order the search settles nodes
	//
	// Always the closest node still outstanding, never the next one along an arc. That is the whole difference from a breadth-first walk, and it is why a cheap long way round still wins.
	//
	// | step | settles | at distance |
	// | --- | --- | --- |
	// | 1 | depot | 0 |
	// | 2 | north | 2 |
	// | 3 | east | 3 |
	// | 4 | ridge | 5 |
	// | 5 | port | 8 |
	// | 6 | beacon | 10 |
	//
	// 6 of 7 nodes were reached, in 7 improvements. An arc that is looked at and rejected costs a comparison; only an improvement costs a write.
	//
	// ## Ties, and why a realm should care
	//
	// Three spokes, all 5 away from the hub. Nothing in the distances separates them, so something else has to, and that something must not be map iteration order: a `Render` that reshuffled between validating nodes would be a consensus bug, not a cosmetic one.
	//
	// | declared | settle order |
	// | --- | --- |
	// | west, south, crater | hub -> west -> south -> crater |
	// | crater, south, west | hub -> crater -> south -> west |
	//
	// The tie resolves to the order the graph was built in, and nothing else. Build it the same way twice and you get the same page twice.
	//
	// ## What it will not do
	//
	// A negative arc panics at `AddEdge`, where the caller can still fix it. Accepting one would not return an error later, it would return a confident wrong answer: the search never revisits a settled node, so a negative arc pointing back at one is simply never seen.
	//
	// | limit | value | why |
	// | --- | --- | --- |
	// | `MaxNodes` | 512 | the frontier holds at most one entry per node, so this bounds memory |
	// | `MaxEdges` | 4000 | arcs bound the work, not the memory |
	// | negative arc | panics | the algorithm's precondition, not a simplification |
	// | self-loop | panics | it can never shorten a path, so it is a caller mistake |
	//
	// Both caps are small on purpose. This is a routing table for a realm, not a road atlas, and a caller that can state the worst case up front can price the gas before it sends the transaction.
}
