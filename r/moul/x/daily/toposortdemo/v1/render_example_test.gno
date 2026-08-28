package toposortdemo

// ExampleRender pins the realm's root Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Topological Sort
	//
	// Ordering a dependency graph so nothing is built before what it needs, demoing the [`p/moul/x/daily/toposort`](/p/moul/x/daily/toposort/v1) library.
	//
	// ## The graph
	//
	// ```
	// avl <- strings
	// markdown <- strings
	// realm <- storage, ui
	// storage <- avl
	// strings
	// ui <- markdown
	// ```
	//
	// ## Install order
	//
	// 1. `strings`
	// 2. `avl`
	// 3. `markdown`
	// 4. `storage`
	// 5. `ui`
	// 6. `realm`
	//
	// Ties are broken lexicographically, so this ordering is the *only* one the library will ever produce for this graph.
	//
	// > See [`/cycle`](/r/moul/x/daily/toposortdemo/v1:cycle) for what happens when the graph is not a DAG.
}

// ExampleRender_cycle pins the failure mode: a cycle is reported with the nodes
// still stuck, rather than silently dropping them.
func ExampleRender_cycle() {
	print(Render("/cycle"))
	// Output:
	// # Topological Sort
	//
	// Ordering a dependency graph so nothing is built before what it needs, demoing the [`p/moul/x/daily/toposort`](/p/moul/x/daily/toposort/v1) library.
	//
	// ## A graph with a cycle
	//
	// ```
	// auth <- session
	// server <- auth
	// session <- auth
	// ```
	//
	// `Sort` returns an error: **toposort: graph has a cycle**
	//
	// Ordered before giving up: _nothing_
	//
	// Stuck on the cycle: `auth`, `server`, `session`
	//
	// > The nodes still stuck are named rather than silently dropped, so a caller can report exactly which dependencies are tangled.
}
