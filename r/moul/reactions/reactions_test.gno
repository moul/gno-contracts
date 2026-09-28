package reactions

import (
	"strconv"
	"strings"
	"testing"

	rx "gno.land/p/moul/reactions/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

const homePage = "gno.land/r/moul/home"

var (
	alice = testutils.TestAddress("alice")
	bob   = testutils.TestAddress("bob")
)

// reset clears realm state. Realm globals live for the whole test binary, and
// the Example runs after every Test, so everything that renders starts here.
func reset() { board = rx.NewBoard() }

func TestReactAndUnreact(cur realm, t *testing.T) {
	reset()

	testing.SetRealm(testing.NewUserRealm(alice))
	React(cross(cur), homePage, rx.KeyUp)
	testing.SetRealm(testing.NewUserRealm(bob))
	React(cross(cur), homePage, rx.KeyFire)

	uassert.Equal(t, 2, Count(homePage))
	uassert.Equal(t, 1, CountOf(homePage, rx.KeyUp))
	uassert.Equal(t, rx.KeyUp, ReactionOf(homePage, alice))
	uassert.Equal(t, 1, Pages())

	key, who, _ := Last(homePage)
	uassert.Equal(t, rx.KeyFire, key)
	uassert.Equal(t, bob, who)

	testing.SetRealm(testing.NewUserRealm(alice))
	Unreact(cross(cur), homePage)
	uassert.Equal(t, 1, Count(homePage))
	uassert.Equal(t, "", ReactionOf(homePage, alice))
}

func TestReadsOnAnUntouchedPageAreZero(t *testing.T) {
	reset()
	uassert.Equal(t, 0, Count("gno.land/r/nobody/here"))
	uassert.Equal(t, 0, CountOf("gno.land/r/nobody/here", rx.KeyUp))
	uassert.Equal(t, "", ReactionOf("gno.land/r/nobody/here", alice))
	key, _, _ := Last("gno.land/r/nobody/here")
	uassert.Equal(t, "", key)
}

func TestReactRefusals(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsWithMessage(t, cur, "reactions: no such reaction: poop", func() {
		React(cross(cur), homePage, "poop")
	})

	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsWithMessage(t, cur, "reactions: not a page key: not a path", func() {
		React(cross(cur), "not a path", rx.KeyUp)
	})

	uassert.Equal(t, 0, Pages(), "a refused reaction creates no page")
}

// TestUnreactAbortsRatherThanNoOp is the deliberate asymmetry: a misspelled
// page key on Unreact has to be visible, or a reader thinks they removed
// something they did not.
func TestUnreactAbortsRatherThanNoOp(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsWithMessage(t, cur, "reactions: nothing to remove on "+homePage, func() {
		Unreact(cross(cur), homePage)
	})
}

// TestRenderBlockForIsWhatTheBlockLinksTo pins the property a host realm
// depends on: every link in the embedded block points at THIS realm, not at
// the realm that embedded it, and carries the page key as an argument.
func TestRenderBlockForIsWhatTheBlockLinksTo(t *testing.T) {
	reset()
	got := RenderBlockFor(homePage)
	uassert.True(t, strings.Contains(got, "(/r/moul/reactions/v0$help&func=React&"),
		"the txlink targets this realm")
	uassert.True(t, strings.Contains(got, "page=gno.land%2Fr%2Fmoul%2Fhome"),
		"and carries the host page as the parameter")
	uassert.False(t, strings.Contains(got, "/r/moul/home$help"),
		"never the host realm, which has no React to call")
}

// TestRenderBlockKeysOnTheCaller is the borrowed-read rule this realm's whole
// ergonomics rest on: RenderBlock has no cur realm parameter, so gno opens no
// frame for it and unsafe.CurrentRealm() reports whoever called.
//
// In-package there is no other realm to call from, so what this pins is the
// half that can be pinned here: RenderBlock agrees with RenderBlockFor when
// the caller IS this realm. The cross-realm half is measured in AGENTS.md
// (2026-09-22) and is the same mechanism r/moul/config's TopBlock uses.
func TestRenderBlockKeysOnTheCaller(t *testing.T) {
	reset()
	uassert.Equal(t, RenderBlockFor(realmPath), RenderBlock())
	uassert.NotEqual(t, RenderBlockFor(homePage), RenderBlock(),
		"and a different page is a different block")
}

func TestRenderPageView(cur realm, t *testing.T) {
	reset()
	testing.SetRealm(testing.NewUserRealm(alice))
	React(cross(cur), homePage, rx.KeyUp)

	got := Render(homePage)
	uassert.True(t, strings.HasPrefix(got, "# gno\\.land/r/moul/home\n"),
		"the heading is the page key, escaped: ui.Inline backslashes the dot")
	uassert.True(t, strings.Contains(got, "Last reaction: \U0001F44D by "))
	uassert.True(t, strings.Contains(got, "Remove my reaction"))
	uassert.True(t, strings.Contains(got, "[The board](/r/moul/reactions/v0)"))
}

func TestRenderRejectsAPathThatIsNotAPageKey(t *testing.T) {
	reset()
	got := Render("[click](http://e.vil)")
	uassert.True(t, strings.HasPrefix(got, "# Not a page\n"))
	uassert.False(t, strings.Contains(got, "](http://e.vil)"),
		"a render path is escaped before it is shown back")
}

// TestRenderHomeShowsTheBoard uses uassert rather than an Example because the
// page contains consecutive blank lines, which gno collapses inside an
// // Output: block.
func TestRenderHomeShowsTheBoard(cur realm, t *testing.T) {
	reset()
	uassert.True(t, strings.Contains(Render(""), "*No page has been reacted to yet.*"))

	testing.SetRealm(testing.NewUserRealm(alice))
	React(cross(cur), homePage, rx.KeyParty)

	got := Render("")
	uassert.True(t, strings.Contains(got,
		"| [gno\\.land/r/moul/home](/r/moul/reactions/v0:gno.land/r/moul/home) | 1 |"),
		"the cell text is escaped, the URL is not: they are different contexts")
	uassert.True(t, strings.Contains(got, "import \"gno.land/r/moul/reactions/v0\""),
		"the homepage is the getting-started doc, and the snippet is copy-pasteable")
	for _, k := range rx.Keys() {
		uassert.True(t, strings.Contains(got, "| `"+k+"` | "+rx.Emoji(k)+" |"), k)
	}
}

// TestBoardIndexIsCapped: the number of pages is unbounded, the index is not.
func TestBoardIndexIsCapped(cur realm, t *testing.T) {
	reset()
	for i := 0; i < maxListed+3; i++ {
		testing.SetRealm(testing.NewUserRealm(alice))
		// Zero-padded, because avl keys sort as strings and ufmt has no width
		// flags: "p9" would otherwise sort between "p10" and "p11".
		n := strconv.Itoa(i)
		if len(n) < 2 {
			n = "0" + n
		}
		React(cross(cur), "gno.land/r/spam/p"+n, rx.KeyUp)
	}
	uassert.Equal(t, maxListed+3, Pages())

	got := Render("")
	uassert.Equal(t, maxListed, strings.Count(got, "(/r/moul/reactions/v0:gno.land/r/spam/"))
	uassert.True(t, strings.Contains(got, "28 pages in total, 25 shown."))
}
