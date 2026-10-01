package kitindexdemo

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// seed builds a fixed board without crossing anything, so an example can set up
// its own state.
//
// An Example has no realm token, so it cannot call Post, and the state the
// tests happen to leave is not a contract. Writing the globals directly is the
// escape hatch AGENTS.md names: same package, no crossing, fully deterministic.
func seed() {
	reset()
	add := func(who address, tag, body string, height int64) {
		id := notes.Add(&note{Author: who, Tag: tag, Body: body, Height: height})
		if err := byTag.Add(tag, id); err != nil {
			panic(err)
		}
		if err := byAuthor.Add(who.String(), id); err != nil {
			panic(err)
		}
	}
	add(alice, "gno", "the index is two containers and one function", 123)
	add(bob, "gno", "and the function is where the correctness is", 124)
	add(alice, "storage", "you are charged for objects, not for data", 125)
}

// The root page carries TWO consecutive blank lines, which an // Output: block
// can never pin: gno collapses them, exactly as Go does. So the root is
// asserted with uassert.Equal and a backtick literal, which preserves them,
// and only the pages without that shape get an Example.
//
// This is the order of preference AGENTS.md names, and the root page is the
// case that forces the second rung.
func TestRenderRoot(t *testing.T) {
	seed()
	want := `# Notes by tag

3 note(s) under 2 tag(s), by 2 author(s).


| tag | notes |
| --- | --- |
| [gno](/r/moul/x/kitindexdemo/v0:tag/gno) | 2 |
| [storage](/r/moul/x/kitindexdemo/v0:tag/storage) | 1 |

[Post a note](/r/moul/x/kitindexdemo/v0$help&func=Post&body=&tag=)

`
	uassert.Equal(t, want, Render(""))
}

// ExampleRender_tag pins one tag's page, which is the lookup the library is for.
func ExampleRender_tag() {
	seed()
	print(Render("tag/gno"))
	// Output:
	// # #gno
	// | # | author | tag | note | height |
	// | --- | --- | --- | --- | --- |
	// | 1 | `g1v9kxjc…40gh` | `gno` | the index is two containers and one function | 123 |
	// | 2 | `g1vfhkyh…vdhu` | `gno` | and the function is where the correctness is | 124 |
}
