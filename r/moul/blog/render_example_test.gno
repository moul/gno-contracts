package blog

import "testing"

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

// TestNoticeBlocksAreTransparentByDefault pins the property that made it safe
// to wrap every view in them: with nothing set on r/moul/config, Render is
// byte-for-byte the inner render. If that ever stops holding, every page of
// this blog gains stray whitespace at the top and the bottom.
func TestNoticeBlocksAreTransparentByDefault(t *testing.T) {
	for _, path := range []string{"", "t/gno", "no-such-post"} {
		if Render(path) != render(path) {
			t.Fatalf("Render(%q) differs from the inner render with no notice configured", path)
		}
	}
}
