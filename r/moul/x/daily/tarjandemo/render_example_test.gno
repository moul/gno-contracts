package tarjandemo

// ExampleRender pins the realm's root Render output as a testable example.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Strongly Connected Components
	//
	// Finding which packages are tangled together, not just whether something is, demoing the [`p/moul/x/daily/tarjan`](/p/moul/x/daily/tarjan/v0) library.
	//
	// ## The graph
	//
	// ```
	// app -> auth, render
	// auth -> session
	// codec
	// render -> widget
	// session -> auth, store
	// store -> codec
	// theme -> render
	// widget -> store, theme
	// ```
	//
	// ## Components
	//
	// 1. `codec`
	// 2. `store`
	// 3. `auth`, `session` **(tangled)**
	// 4. `render`, `theme`, `widget` **(tangled)**
	// 5. `app`
	//
	// Two groups came back with more than one member, and those are the cycles:
	//
	// - `auth` <-> `session`
	// - `render` <-> `theme` <-> `widget`
	//
	// Everything else is alone in its own component, which is what an ordinary acyclic package looks like. The list is in reverse topological order: nothing can reach anything listed above it, so reading it top to bottom is a safe build order, treating each tangle as one unit.
	//
	// > Drop one back edge per knot and both come apart: see [`/fixed`](/r/moul/x/daily/tarjandemo/v0:fixed).
}

// ExampleRender_fixed pins the repaired graph, where every component holds
// exactly one node.
func ExampleRender_fixed() {
	print(Render("/fixed"))
	// Output:
	// # Strongly Connected Components
	//
	// Finding which packages are tangled together, not just whether something is, demoing the [`p/moul/x/daily/tarjan`](/p/moul/x/daily/tarjan/v0) library.
	//
	// ## The graph
	//
	// ```
	// app -> auth, render
	// auth -> session
	// codec
	// render -> widget
	// session -> store
	// store -> codec
	// theme
	// widget -> store, theme
	// ```
	//
	// ## Components
	//
	// 1. `codec`
	// 2. `store`
	// 3. `session`
	// 4. `auth`
	// 5. `theme`
	// 6. `widget`
	// 7. `render`
	// 8. `app`
	//
	// Removing `session -> auth` and `theme -> render`, one back edge per knot, left every component holding exactly one node, which is what an acyclic graph looks like through this lens. The node list is unchanged and so is every other edge: a cycle is a property of the edges that close it, not of the packages in it.
}
