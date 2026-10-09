package toolbox

// ExampleRender pins the directory page. The catalog is compiled in, so this
// output changes only when a tool is added or re-described, which is exactly
// when a reviewer should see the diff.
func ExampleRender() {
	print(Render(""))
	// Output:
	// # Toolbox
	//
	// Small utilities on gno.land. Each one is its own realm, composing contracts that are already on chain and showing the answer as a page instead of as a query you have to compose.
	//
	// | Tool | What it does | Tags |
	// | --- | --- | --- |
	// | [Usernames](/r/moul/toolbox/usernames) | Resolve a gno\.land username to an address, or an address to a username\. | identity, read |
	//
	// Tags: [identity](/r/moul/toolbox?tag=identity) · [read](/r/moul/toolbox?tag=read)
	//
	// ## What a tool is
	//
	// - A realm at `gno.land/r/moul/toolbox/<slug>`, reachable on its own.
	// - Read-only unless it says otherwise: a page you open, not a transaction you sign.
	// - Composed from contracts already on chain, so the toolbox adds the view and not the data.
}
