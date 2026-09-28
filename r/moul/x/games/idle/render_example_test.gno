package idle

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

// TestRenderRoutes pins that Render dispatches on the path: empty is the
// board, anything else is read as an address.
func TestRenderRoutes(t *testing.T) {
	reset()
	alice := testutils.TestAddress("alice")
	// Anchored at the block clock, not at t0: Render reads now().
	start(alice, now())

	uassert.True(t, strings.Contains(Render(""), "The Mine"), "empty path is the board")
	uassert.True(t, strings.Contains(Render(alice.String()), "'s mine"), "an address is a card")
	uassert.True(t, strings.Contains(Render("  "+alice.String()+"  "), "'s mine"),
		"a padded address is still a card")
	uassert.True(t, strings.Contains(Render("g1nobody"), "No mine at"), "a stranger is handled")
}

// ExampleRender pins the realm's empty board. It resets the tree first because
// examples run after every Test in the package and would otherwise render
// whatever they left behind.
func ExampleRender() {
	reset()
	print(Render(""))
	// Output:
	// # The Mine
	//
	// Ore accrues while you are away. The mine holds 120 periods of production and then spills, so the only thing that costs you anything is not showing up.
	//
	// *Nobody is digging yet.*
	//
	// [Open a mine](/r/moul/x/games/idle/v0$help&func=Start) | [Claim](/r/moul/x/games/idle/v0$help&func=Claim) | [Upgrade](/r/moul/x/games/idle/v0$help&func=Upgrade) | [Prestige](/r/moul/x/games/idle/v0$help&func=Prestige)
}
