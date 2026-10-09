package usernames

// ExampleRender pins the tool's landing page.
//
// The landing page only, deliberately: a result page reads r/sys/users, whose
// state is whatever the tests in this package left behind, and an example runs
// after all of them. The results are asserted in render_test.gno instead.
func ExampleRender() {
	print(Render(""))
	// Output:
	// [toolbox](/r/moul/toolbox/v0) / **Usernames**
	//
	// # Usernames
	//
	// Who holds a name, and what name an address holds. Type either one.
	//
	// <gno-form path="lookup">
	// <gno-input name="q" type="text" placeholder="username or g1 address" />
	// </gno-form>
	//
	// ## What this answers
	//
	// - The address behind a username, and the username behind an address.
	// - Whether the name you typed is their **current** name or one they renamed away from.
	// - The canonical key the name collapses to, and who already holds that key.
	//
	// ## The same thing from a terminal
	//
	// This page is `r/sys/users` read through `vm/qeval`, with the follow-up questions already asked:
	//
	// ```sh
	// gnokey query vm/qeval -remote https://rpc.gno.land \
	//   -data 'gno.land/r/moul/toolbox/usernames/v0.Resolve("moul")'
	// ```
	//
	// Try [moul](/r/moul/toolbox/usernames/v0:moul), or paste an address into the box above.
}
