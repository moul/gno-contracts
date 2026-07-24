package counter

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils"
	"gno.land/p/nt/uassert"
)

// TestIncDecReset drives the full mutation lifecycle across two callers and
// checks value, total count, and history accounting.
func TestIncDecReset(cur realm, t *testing.T) {
	// reset package-level state for a clean run
	value = 0
	total = 0
	history = nil

	alice := testutils.TestAddress("alice")
	bob := testutils.TestAddress("bob")

	testing.SetRealm(testing.NewUserRealm(alice))
	uassert.Equal(t, 1, Inc(cross(cur)))
	uassert.Equal(t, 2, Inc(cross(cur)))

	testing.SetRealm(testing.NewUserRealm(bob))
	uassert.Equal(t, 1, Dec(cross(cur)))

	uassert.Equal(t, 1, Value())
	uassert.Equal(t, 3, Total())
	uassert.Equal(t, 3, len(history))

	// Reset should bring the value to zero with a delta of -1.
	uassert.Equal(t, 0, Reset(cross(cur)))
	uassert.Equal(t, 0, Value())
	uassert.Equal(t, 4, Total())

	last := history[len(history)-1]
	uassert.Equal(t, -1, last.delta)
	uassert.Equal(t, 0, last.value)
	uassert.Equal(t, bob.String(), last.caller.String())
}

// TestHistoryCapAndRender checks the rolling 20-entry cap and that Render
// reflects the current value and total.
func TestHistoryCapAndRender(cur realm, t *testing.T) {
	value = 0
	total = 0
	history = nil

	caller := testutils.TestAddress("counter")
	testing.SetRealm(testing.NewUserRealm(caller))

	// Apply 25 increments; history must cap at maxHistory (20), total = 25.
	for i := 0; i < 25; i++ {
		Inc(cross(cur))
	}

	uassert.Equal(t, 25, Value())
	uassert.Equal(t, 25, Total())
	uassert.Equal(t, maxHistory, len(history))

	// Oldest surviving entry should have value 6 (changes 1..5 dropped).
	uassert.Equal(t, 6, history[0].value)

	out := Render("")
	uassert.True(t, strings.Contains(out, "# 25"), "render shows current value")
	uassert.True(t, strings.Contains(out, "Total changes:"), "render shows total")
	uassert.True(t, strings.Contains(out, "| +1 |"), "render shows a delta cell")
}

// TestRenderEmpty verifies the empty-state message before any mutations.
func TestRenderEmpty(t *testing.T) {
	value = 0
	total = 0
	history = nil

	out := Render("")
	uassert.True(t, strings.Contains(out, "No changes yet"), "shows empty state")
	uassert.True(t, strings.Contains(out, "# 0"), "shows zero value")
}
