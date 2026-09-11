package rpgroom

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

// ExampleRender pins the empty-room view. resetState() puts the realm back to
// its init() shape, so the example does not depend on test ordering.
func ExampleRender() {
	resetState()
	print(Render(""))
	// Output:
	// # RPG Room
	//
	// A single dungeon room with one monster in it at a time. Call `Spawn("name")` to enter, `Attack()` to fight the resident monster, `Rest()` to heal up, and `Revive()` if you fall.
	//
	// ## Current monster
	//
	// **Slime** — level 1
	//
	// `##########` 35/35 HP
	//
	// - Attack: 5
	// - Monsters cleared so far: 0
	//
	// ## Leaderboard
	//
	// _No heroes yet. Be the first: `Spawn("name")`._
}

// TestRenderLeaderboard checks spawned heroes replace the empty notice and are
// listed in rank order.
func TestRenderLeaderboard(cur realm, t *testing.T) {
	resetState()

	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("alice")))
	Spawn(cross(cur), "Alice the Bold")
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("bob")))
	Spawn(cross(cur), "Bob the Brave")

	out := Render("")
	uassert.False(t, strings.Contains(out, "_No heroes yet"), "empty notice should be gone")
	uassert.True(t, strings.Contains(out, "| # | Hero | Lvl | HP | Kills | Gold | Status |"),
		"leaderboard header should render")
	uassert.True(t, strings.Contains(out, "Alice the Bold"), "alice should be listed")
	uassert.True(t, strings.Contains(out, "Bob the Brave"), "bob should be listed")
	uassert.True(t, strings.Contains(out, "| alive |"), "a fresh hero is alive")
}

// TestRenderHeroPage checks the per-address detail route.
func TestRenderHeroPage(cur realm, t *testing.T) {
	resetState()
	alice := testutils.TestAddress("alice")

	testing.SetRealm(testing.NewUserRealm(alice))
	Spawn(cross(cur), "Alice the Bold")

	out := Render(alice.String())
	uassert.True(t, strings.HasPrefix(out, "# Alice the Bold\n"), "hero page should be titled by name")
	uassert.True(t, strings.Contains(out, "- Level: 1\n"), "level should be shown")
	uassert.True(t, strings.Contains(out, "- Kills: 0\n"), "kills should be shown")
	uassert.True(t, strings.Contains(out, "- Gold: 0\n"), "gold should be shown")
	uassert.False(t, strings.Contains(out, "- Status: fallen"), "a live hero has no fallen status")
}

// TestRenderUnknownHero covers the not-found branch of the detail route.
func TestRenderUnknownHero(t *testing.T) {
	resetState()
	stranger := testutils.TestAddress("stranger").String()

	uassert.Equal(t, "> [!WARNING]\n> No hero found for `"+stranger+"`.\n", Render(stranger))
}

// TestRenderTrimsPath checks surrounding whitespace still routes to the room.
func TestRenderTrimsPath(t *testing.T) {
	resetState()
	uassert.Equal(t, Render(""), Render("   "))
}

// TestRenderMonsterHPBar checks the monster's bar tracks damage.
func TestRenderMonsterHPBar(t *testing.T) {
	resetState()
	monster.HP = monster.MaxHP / 2

	uassert.True(t, strings.Contains(Render(""), hpBar(monster.HP, monster.MaxHP)),
		"the room should render the monster's current HP bar")
}
