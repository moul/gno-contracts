package threads

import (
	"strconv"
	"strings"
	"testing"

	sc "gno.land/p/moul/x/social/coin/v0"
	th "gno.land/p/moul/x/social/threads/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/urequire/v0"
)

const homePage = "gno.land/r/moul/home"

var (
	alice = testutils.TestAddress("alice")
	bob   = testutils.TestAddress("bob")
	carol = testutils.TestAddress("carol")
)

// reset clears realm state. Realm globals live for the whole test binary, so
// everything a later test reads, including the ledger, starts here.
//
// The ledger is rebuilt through a same-realm cross because grc20.NewToken
// needs a code-realm frame, which a test's EOA-origin cur is not. It is NOT
// re-registered with grc20reg: the registry is another realm and its entry
// survives this one's state.
func reset(cur realm) {
	board = th.NewBoard()
	func(cur realm) { // the name is forced: a realm argument must be called cur
		points = sc.New("Thread Points", "THREAD", 0, 0, tokenPolicy, 0, cur)
	}(cross(cur))
}

// earn gives who n THREAD the only way the realm allows: n distinct addresses
// replying to a thread they wrote.
func earn(cur realm, t *testing.T, who address, n int) int64 {
	t.Helper()
	testing.SetRealm(testing.NewUserRealm(who))
	id := Post(cross(cur), homePage, "a thread by "+who.String())
	for i := 0; i < n; i++ {
		testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("replier" + strconv.Itoa(i))))
		Reply(cross(cur), id, "hello")
	}
	return id
}

func TestAnAuthorEarnsPeopleAndNotMessages(cur realm, t *testing.T) {
	reset(cur)

	testing.SetRealm(testing.NewUserRealm(alice))
	id := Post(cross(cur), homePage, "first thread")
	uassert.Equal(t, int64(0), BalanceOf(alice), "writing earns nothing on its own")

	testing.SetRealm(testing.NewUserRealm(bob))
	Reply(cross(cur), id, "nice")
	uassert.Equal(t, int64(1), BalanceOf(alice))

	testing.SetRealm(testing.NewUserRealm(bob))
	Reply(cross(cur), id, "still me")
	uassert.Equal(t, int64(1), BalanceOf(alice), "one person is one point, however much they say")

	testing.SetRealm(testing.NewUserRealm(alice))
	Reply(cross(cur), id, "thanks")
	uassert.Equal(t, int64(1), BalanceOf(alice), "replying to yourself is not an audience")

	testing.SetRealm(testing.NewUserRealm(carol))
	Reply(cross(cur), id, "hi")
	uassert.Equal(t, int64(2), BalanceOf(alice))

	uassert.Equal(t, 2, Repliers(id))
	uassert.Equal(t, int64(2), TotalSupply())
	uassert.Equal(t, int64(0), BalanceOf(bob), "a replier earns nothing")
}

func TestBoostIsTheOnlyThingThatBurns(cur realm, t *testing.T) {
	reset(cur)
	id := earn(cur, t, alice, 10)
	urequire.Equal(t, int64(10), BalanceOf(alice))

	testing.SetRealm(testing.NewUserRealm(alice))
	Boost(cross(cur), id)

	uassert.Equal(t, int64(0), BalanceOf(alice))
	uassert.Equal(t, int64(0), TotalSupply(), "the sink removes supply, it does not move it")
	uassert.Equal(t, int64(123+PinBlocks), PinnedUntil(id), "tests start at height 123")
}

func TestBoostRefusesWhatTheCallerCannotAfford(cur realm, t *testing.T) {
	reset(cur)
	id := earn(cur, t, alice, 1)

	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "balance 1 is short of 10", func() {
		Boost(cross(cur), id)
	})
	uassert.Equal(t, int64(0), PinnedUntil(id), "a refused boost pins nothing")
	uassert.Equal(t, int64(1), BalanceOf(alice))
}

// A second boost extends from the current pin, not from now, so the thread
// never loses time it was already paid for.
func TestASecondBoostExtendsRatherThanRestarts(cur realm, t *testing.T) {
	reset(cur)
	id := earn(cur, t, alice, 20)

	testing.SetRealm(testing.NewUserRealm(alice))
	Boost(cross(cur), id)
	first := PinnedUntil(id)

	testing.SetRealm(testing.NewUserRealm(alice))
	Boost(cross(cur), id)
	uassert.Equal(t, first+PinBlocks, PinnedUntil(id))
	uassert.Equal(t, int64(0), BalanceOf(alice))
}

// Anyone may boost anyone's thread, and the buyer has to get THREAD from
// somebody who earned it. That is the whole market.
func TestPlacementIsBoughtFromAnEarner(cur realm, t *testing.T) {
	reset(cur)
	id := earn(cur, t, alice, 10)

	testing.SetRealm(testing.NewUserRealm(alice))
	Transfer(cross(cur), bob, 10)
	uassert.Equal(t, int64(0), BalanceOf(alice))
	uassert.Equal(t, int64(10), BalanceOf(bob))

	testing.SetRealm(testing.NewUserRealm(bob))
	Boost(cross(cur), id)
	uassert.True(t, PinnedUntil(id) > 0, "bob pinned alice's thread")
	uassert.Equal(t, int64(0), TotalSupply())
}

func TestPostRefusals(cur realm, t *testing.T) {
	reset(cur)
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "not a page key", func() {
		Post(cross(cur), "nopath", "body")
	})
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "body is empty", func() {
		Post(cross(cur), homePage, "   ")
	})
	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.AbortsContains(t, cur, "no such thread", func() {
		Reply(cross(cur), 99, "into the void")
	})
	uassert.Equal(t, 0, Total())
}

func TestCountsAreScopedToTheirPage(cur realm, t *testing.T) {
	reset(cur)
	testing.SetRealm(testing.NewUserRealm(alice))
	Post(cross(cur), homePage, "on home")
	testing.SetRealm(testing.NewUserRealm(alice))
	Post(cross(cur), "gno.land/r/moul/blog", "on the blog")

	uassert.Equal(t, 1, Count(homePage))
	uassert.Equal(t, 0, Count("gno.land/r/nobody/here"))
	uassert.Equal(t, 2, Total())
	uassert.Equal(t, 2, Pages())
}

// RenderBlockFor is the embed, and it escapes what it shows: a raw pipe in a
// body would otherwise open a column in the host realm's page.
func TestRenderBlockForEscapesTheBody(cur realm, t *testing.T) {
	reset(cur)
	testing.SetRealm(testing.NewUserRealm(alice))
	Post(cross(cur), homePage, "a | pipe")

	got := RenderBlockFor(homePage)
	uassert.True(t, strings.Contains(got, "func=Post"), "the block offers the transaction: "+got)
	uassert.True(t, strings.Contains(got, `| a \| pipe |`),
		"the body cell escapes the pipe rather than opening a column: "+got)
	uassert.False(t, strings.Contains(got, "| a | pipe"), "no raw pipe survives: "+got)
	uassert.True(t, strings.Contains(RenderBlockFor("gno.land/r/nobody/here"), "No discussion yet."))
}

// TestRender uses uassert rather than an Example because every view contains
// consecutive blank lines, which gno collapses inside an // Output: block.
func TestRender(cur realm, t *testing.T) {
	reset(cur)
	testing.SetRealm(testing.NewUserRealm(alice))
	id := Post(cross(cur), homePage, "a thread about [links](x)")
	testing.SetRealm(testing.NewUserRealm(bob))
	Reply(cross(cur), id, "a reply with a | pipe")

	index := Render("")
	uassert.True(t, strings.Contains(index, "| 1 | 1 | 1 |"), "threads, pages, supply: "+index)
	uassert.True(t, strings.Contains(index, tokenPolicy.Sink), "the index declares the sink")
	uassert.True(t, strings.Contains(index, `import "`+realmPath+`"`), "the index is the embed doc")

	page := Render("page/" + homePage)
	uassert.True(t, strings.Contains(page, "/r/moul/home"), "it links the page itself: "+page)
	uassert.True(t, strings.Contains(page, "func=Post"))

	sid := strconv.FormatInt(id, 10)
	thread := Render("thread/" + sid)
	uassert.True(t, strings.Contains(thread, "# Thread #"+sid))
	uassert.True(t, strings.Contains(thread, "a thread about \\[links\\]\\(x\\)"),
		"the body is escaped where it is shown: "+thread)
	uassert.True(t, strings.Contains(thread, "a reply with a \\| pipe"),
		"a reply cell cannot open a column: "+thread)
	uassert.True(t, strings.Contains(thread, "func=Boost"))

	uassert.Equal(t, "# Threads\nNo thread #4242", Render("thread/4242"))
	uassert.Equal(t, "# Threads\nNot a thread id: nope", Render("thread/nope"))
	uassert.Equal(t, "# Threads\nNot a page key: nope", Render("page/nope"))
	uassert.True(t, strings.HasPrefix(Render("elsewhere"), "# Not found"))
}

func TestTokenIsDiscoverableWithoutImportingThisRealm(t *testing.T) {
	uassert.True(t, strings.HasSuffix(TokenKey(), ".THREAD"), TokenKey())
	uassert.True(t, strings.Contains(TokenKey(), realmPath), TokenKey())
}
