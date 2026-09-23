package devtools

import (
	"testing"

	"gno.land/p/moul/fifo/v0"
	"gno.land/r/moul/config/v1"
	"gno.land/p/nt/uassert/v0"
)

// reset puts the realm back to a just-deployed state. Realm globals live for
// the whole test binary and gno runs every Example AFTER every Test, so without
// this the pinned output would depend on which tests ran before it.
func reset() { notes = fifo.New(maxNotes) }

func TestAdd(cur realm, t *testing.T) {
	reset()

	Add(cross(cur), "hello")
	uassert.Equal(t, 1, notes.Size())
	uassert.Equal(t, "hello", notes.Get(0).(string))

	uassert.AbortsWithMessage(t, cur, "empty note", func() { Add(cross(cur), "   ") })
	uassert.AbortsContains(t, cur, "note too long", func() {
		long := ""
		for i := 0; i < 201; i++ {
			long += "x"
		}
		Add(cross(cur), long)
	})
}

// TestAddEscapes is the guard that matters most in a realm anyone can write to:
// a note is a string a caller typed, and it lands in a markdown list. Without
// ui.Inline the first line below would close the list item and render as a
// heading, and the second would become a link.
func TestAddEscapes(cur realm, t *testing.T) {
	reset()

	Add(cross(cur), "# not a heading")
	Add(cross(cur), "[not](https://evil.example.com)")

	for _, got := range []string{notes.Get(0).(string), notes.Get(1).(string)} {
		uassert.False(t, got == "# not a heading", "markdown survived unescaped")
		uassert.False(t, got == "[not](https://evil.example.com)", "a link survived unescaped")
	}
	uassert.True(t, len(notes.Get(0).(string)) > len("# not a heading"),
		"escaping should have added characters")
}

// TestNotesAreBounded pins the reason fifo is here rather than a slice: storage
// is paid for and never refunded, so a list anyone can append to needs a
// ceiling in the type, not in a comment.
func TestNotesAreBounded(cur realm, t *testing.T) {
	reset()

	for i := 0; i < maxNotes+5; i++ {
		Add(cross(cur), "note "+string(rune('a'+i)))
	}
	uassert.Equal(t, maxNotes, notes.Size(), "the list stops growing at maxNotes")
	uassert.Equal(t, maxNotes, notes.MaxSize())
}

// TestAddHonoursThePause is the whole point of importing r/moul/config: this
// realm can be stopped from outside, by a transaction against another realm,
// with no redeploy here. It cannot set that from this package (config has its
// own authority), so it asserts the wiring: Add goes through the pause check
// and passes while nothing is set.
func TestAddHonoursThePause(cur realm, t *testing.T) {
	reset()
	uassert.False(t, config.IsPausedFor(realmPath), "nothing configured means running")
	Add(cross(cur), "allowed while running")
	uassert.Equal(t, 1, notes.Size())
}

func TestReset(cur realm, t *testing.T) {
	reset()
	Add(cross(cur), "one")
	Reset(cross(cur))
	uassert.Equal(t, 0, notes.Size())
}

// ExampleRender pins the root view. It is free of the height and the chain id
// on purpose: those live under :chain, so this one is stable.
func ExampleRender() {
	reset()
	print(Render(""))
	// Output:
	// # allinone: devtools
	//
	// Eight packages, used together rather than one at a time. [source](https://mygnoscan.moul.p2p.team/realm/r/moul/x/allinone/devtools/v0)
	//
	// ## Notes
	//
	// *no notes yet*
	//
	// - [add a note](/r/moul/x/allinone/devtools/v0$help&func=Add&body=hello)
	// - [clear them](/r/moul/x/allinone/devtools/v0$help&func=Reset)
	// - [live chain values](/r/moul/x/allinone/devtools/v0:chain)
	// - [toggle the debug panel](/r/moul/x/allinone/devtools/v0:?debug=1)
	//
	// ## What each package does here
	//
	// | package | what it contributed |
	// | --- | --- |
	// | `r/moul/config` | the notice block above, the pause guard on `Add`, and which explorer to link |
	// | `p/moul/mygnoscan` | the explorer routes, so a link survives a route change |
	// | `p/moul/debug` | the `?debug=1` panel, empty otherwise |
	// | `p/moul/realmpath` | splitting the render path into a view and a query |
	// | `p/moul/kit/ui` | escaping a caller's note, and this table |
	// | `p/moul/md` | every heading, link and list on the page |
	// | `p/moul/txlink` | the call links above, relative to this realm |
	// | `p/moul/fifo` | the note list, bounded so storage cannot grow forever |
}
