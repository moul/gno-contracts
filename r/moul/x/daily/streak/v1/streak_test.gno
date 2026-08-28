package streak

import (
	"strconv"
	"strings"
	"testing"

	"chain/runtime"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

// reset clears realm state between tests.
func reset() { users = avl.NewTree() }

// alignDay moves to the start of the next check-in window, so a test begins on
// a clean day boundary. testing only exposes a RELATIVE SkipHeights (there is
// no absolute height setter, and no testing.Height), so days are driven
// forward from wherever the previous test left the chain — never assume an
// absolute day number, ask Day().
func alignDay() {
	if rem := runtime.ChainHeight() % BlocksPerDay; rem != 0 {
		testing.SkipHeights(BlocksPerDay - rem)
	}
}

// advanceDays moves the chain forward by n whole windows.
func advanceDays(n int64) { testing.SkipHeights(n * BlocksPerDay) }

// checkIn runs a check-in as addr.
func checkIn(cur realm, addr address) int {
	testing.SetRealm(testing.NewUserRealm(addr))
	return CheckIn(cross(cur))
}

func TestFirstCheckInStartsAtOne(cur realm, t *testing.T) {
	reset()
	alignDay()
	alice := testutils.TestAddress("alice")

	uassert.Equal(t, 1, checkIn(cur, alice))
	uassert.Equal(t, 1, Current(alice))
	uassert.Equal(t, 1, Best(alice))
}

func TestConsecutiveDaysExtendStreak(cur realm, t *testing.T) {
	reset()
	alignDay()
	alice := testutils.TestAddress("alice")

	uassert.Equal(t, 1, checkIn(cur, alice))
	advanceDays(1)
	uassert.Equal(t, 2, checkIn(cur, alice))
	advanceDays(1)
	uassert.Equal(t, 3, checkIn(cur, alice))
	uassert.Equal(t, 3, Best(alice))
}

// The whole point of the realm: a missed window restarts the run at 1, but the
// record survives.
func TestMissedDayResetsCurrentButKeepsBest(cur realm, t *testing.T) {
	reset()
	alignDay()
	alice := testutils.TestAddress("alice")

	checkIn(cur, alice)
	advanceDays(1)
	checkIn(cur, alice)
	uassert.Equal(t, 2, Best(alice))

	advanceDays(7) // a long gap
	uassert.Equal(t, 1, checkIn(cur, alice))
	uassert.Equal(t, 1, Current(alice))
	uassert.Equal(t, 2, Best(alice))
}

func TestTwiceInSameDayPanics(cur realm, t *testing.T) {
	reset()
	alignDay()
	alice := testutils.TestAddress("alice")
	checkIn(cur, alice)

	testing.SetRealm(testing.NewUserRealm(alice))
	rec := revive(func() { CheckIn(cross(cur)) })
	uassert.True(t, rec != nil)
}

// Current() reports the live truth: once the window lapses the streak is 0,
// even though the stored record still holds the old value until the next
// check-in rewrites it.
func TestCurrentGoesStaleWithoutACheckIn(cur realm, t *testing.T) {
	reset()
	alignDay()
	alice := testutils.TestAddress("alice")
	checkIn(cur, alice)

	advanceDays(1) // yesterday — still within reach
	uassert.Equal(t, 1, Current(alice))
	advanceDays(1) // gap: the run is over
	uassert.Equal(t, 0, Current(alice))
	uassert.Equal(t, 1, Best(alice)) // record untouched
}

func TestStreaksAreIndependentPerAddress(cur realm, t *testing.T) {
	reset()
	alignDay()
	alice := testutils.TestAddress("alice")
	bob := testutils.TestAddress("bob")

	checkIn(cur, alice)
	advanceDays(1)
	checkIn(cur, alice)
	checkIn(cur, bob)

	uassert.Equal(t, 2, Current(alice))
	uassert.Equal(t, 1, Current(bob))
}

func TestUnknownAddressIsZero(t *testing.T) {
	reset()
	carol := testutils.TestAddress("carol")
	uassert.Equal(t, 0, Current(carol))
	uassert.Equal(t, 0, Best(carol))
}

func TestRenderEmptyBoard(t *testing.T) {
	reset()
	out := Render("")
	uassert.True(t, strings.Contains(out, "Nobody has checked in yet"))
	uassert.True(t, strings.Contains(out, "Current day: **"+strconv.FormatInt(Day(), 10)+"**"))
}

func TestRenderRanksByBest(cur realm, t *testing.T) {
	reset()
	alignDay()
	alice := testutils.TestAddress("alice")
	bob := testutils.TestAddress("bob")
	// alice reaches 2, bob only 1
	checkIn(cur, alice)
	advanceDays(1)
	checkIn(cur, alice)
	checkIn(cur, bob)

	out := Render("")
	ai := strings.Index(out, alice.String())
	bi := strings.Index(out, bob.String())
	uassert.True(t, ai >= 0)
	uassert.True(t, bi >= 0)
	uassert.True(t, ai < bi) // alice ranks first
}

func TestRenderSingleAddress(cur realm, t *testing.T) {
	reset()
	alignDay()
	alice := testutils.TestAddress("alice")
	checkIn(cur, alice)

	out := Render("/" + alice.String())
	uassert.True(t, strings.Contains(out, "current streak: **1**"))
	uassert.True(t, strings.Contains(out, "total check-ins: **1**"))
}

func TestRenderRejectsBadAddress(t *testing.T) {
	reset()
	out := Render("/not-an-address")
	uassert.True(t, strings.Contains(out, "Not a valid address"))
}
