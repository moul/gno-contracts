package blog

// ExampleRender pins the index. It seeds state directly (rather than through
// Set) so the example takes no `cur realm`, and it resets first because an
// example runs after every Test in the package and would otherwise render what
// they left behind.
func ExampleRender() {
	reset()
	seed("mygnoscan", "Sharing mygnoscan", "2026-09-23", "mygnoscan,tooling", "An unfinished BI tool for gno.land.")
	seed("hello", "Hello", "2026-09-01", "meta", "Starting a blog on chain.")
	print(Render(""))
	// Output:
	// # moul's blog
	//
	// Notes on gno.land, from the person building on it.
	//
	// ## [Sharing mygnoscan](/r/moul/blog:mygnoscan)
	//
	// 2026-09-23 · [#mygnoscan](/r/moul/blog:t/mygnoscan) · [#tooling](/r/moul/blog:t/tooling)
	//
	// An unfinished BI tool for gno\.land\.
	//
	// ## [Hello](/r/moul/blog:hello)
	//
	// 2026-09-01 · [#meta](/r/moul/blog:t/meta)
	//
	// Starting a blog on chain\.
}
