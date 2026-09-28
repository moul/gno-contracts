package idle

import (
	"strings"
	"testing"

	"gno.land/p/nt/avl/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

// reset clears the realm between tests. Package state carries over from one
// test to the next even though the block height does not, so every test that
// looks at the board has to start from a known tree.
func reset() { mines = avl.Tree{} }

// t0 is an arbitrary unix second to hang the tests off. Nothing asserts an
// absolute time, only differences from this one.
//
// It is only legal for the non-crossing helpers, which take the time as an
// argument. Anything reaching now() (Render and the read helpers) reads the
// BLOCK timestamp, which in a test is far below t0, so a mine anchored here
// would make the chain's clock look like it ran backwards. Those tests anchor
// at now() instead.
const t0 = int64(1700000000)

func TestStartOpensALevelOneMine(t *testing.T) {
	reset()
	alice := testutils.TestAddress("alice")

	out := start(alice, t0)
	uassert.True(t, strings.Contains(out, "level 1"), "expected the opening message")

	m, ok := get(alice)
	uassert.True(t, ok, "expected a mine")
	uassert.Equal(t, int64(1), m.level)
	uassert.Equal(t, int64(0), m.prestige)
	uassert.Equal(t, t0, m.anchor)
	uassert.Equal(t, int64(0), m.pending)
}

func TestStartTwicePanics(cur realm, t *testing.T) {
	reset()
	alice := testutils.TestAddress("alice")
	start(alice, t0)
	uassert.PanicsContains(t, cur, "already have a mine", func() { start(alice, t0) })
}

func TestActingWithoutAMinePanics(cur realm, t *testing.T) {
	reset()
	bob := testutils.TestAddress("bob")
	uassert.PanicsContains(t, cur, "no mine yet", func() { claim(bob, t0) })
	uassert.PanicsContains(t, cur, "no mine yet", func() { upgrade(bob, t0) })
	uassert.PanicsContains(t, cur, "no mine yet", func() { prestige(bob, t0) })
}

func TestAccrualAndClaim(t *testing.T) {
	reset()
	alice := testutils.TestAddress("alice")
	start(alice, t0)

	m, _ := get(alice)
	uassert.Equal(t, int64(0), m.view(t0+Period-1), "nothing before the first whole period")
	uassert.Equal(t, int64(1), m.view(t0+Period), "one ore after one period")
	uassert.Equal(t, int64(30), m.view(t0+30*Period))

	out := claim(alice, t0+30*Period)
	uassert.True(t, strings.Contains(out, "Claimed 30 ore"), "got: "+out)
	uassert.Equal(t, int64(30), m.banked)
	uassert.Equal(t, int64(30), m.lifetime)
	uassert.Equal(t, int64(0), m.pending)
	uassert.Equal(t, int64(1), m.claims)
}

func TestClaimingNothingPanics(cur realm, t *testing.T) {
	reset()
	alice := testutils.TestAddress("alice")
	start(alice, t0)
	uassert.PanicsContains(t, cur, "nothing to claim", func() { claim(alice, t0+Period-1) })
}

// TestClaimCadenceDoesNotMatter is the game-level statement of the invariant
// the accrual package exists for: two players who dig for the same span end up
// with the same ore whatever their claiming habits. A realm that re-anchored
// to now would pay the busy player less, and a realm that decayed would pay
// them more.
//
// "Whatever their habits" has exactly one limit, and it is the design rather
// than the arithmetic: a cadence longer than the mine takes to fill spills,
// and is meant to. Every cadence here stays under that, and
// TestTheMineSpills covers the other side.
func TestClaimCadenceDoesNotMatter(t *testing.T) {
	const span = 600 * Period
	fill := CapPeriods * Period

	for _, cadence := range []int64{Period, 2*Period + 1, 7 * Period, 599, 6001, fill} {
		if cadence > fill {
			t.Fatalf("cadence %d would spill, which is not what this test is about", cadence)
		}
		reset()
		alice := testutils.TestAddress("alice")
		start(alice, t0)
		m, _ := get(alice)

		for at := t0 + cadence; at <= t0+span; at += cadence {
			if m.view(at) > 0 {
				claim(alice, at)
			}
		}
		if m.view(t0+span) > 0 {
			claim(alice, t0+span)
		}
		uassert.Equal(t, int64(600), m.lifetime, "cadence changed the payout")
	}
}

// TestTheMineSpills pins the ceiling: production past the cap is lost, and
// coming back late is what costs you, which is decision 1 of the design.
func TestTheMineSpills(t *testing.T) {
	reset()
	alice := testutils.TestAddress("alice")
	start(alice, t0)
	m, _ := get(alice)

	uassert.Equal(t, CapPeriods, m.view(t0+CapPeriods*Period), "full exactly at the cap")
	uassert.Equal(t, CapPeriods, m.view(t0+10*CapPeriods*Period), "and no more, ever")

	claim(alice, t0+10*CapPeriods*Period)
	uassert.Equal(t, CapPeriods, m.lifetime, "ten cap-fulls of absence paid one")
}

func TestFullAtIsTheOnlyDeadline(t *testing.T) {
	reset()
	alice := testutils.TestAddress("alice")
	start(alice, t0)
	m, _ := get(alice)

	uassert.Equal(t, t0+CapPeriods*Period, m.fullAt(t0), "an empty mine fills in CapPeriods")

	half := t0 + (CapPeriods/2)*Period
	uassert.Equal(t, half+(CapPeriods/2)*Period, m.fullAt(half), "half full, half the time left")

	late := t0 + 99*CapPeriods*Period
	uassert.Equal(t, late, m.fullAt(late), "already full reads as now")
}

func TestUpgrade(t *testing.T) {
	reset()
	alice := testutils.TestAddress("alice")
	start(alice, t0)
	m, _ := get(alice)

	uassert.Equal(t, UpgradeBase, upgradeCost(1))
	uassert.Equal(t, 4*UpgradeBase, upgradeCost(2))

	claim(alice, t0+UpgradeBase*Period)
	out := upgrade(alice, t0+UpgradeBase*Period)
	uassert.True(t, strings.Contains(out, "Level 2"), "got: "+out)
	uassert.Equal(t, int64(2), m.level)
	uassert.Equal(t, int64(0), m.banked, "the upgrade spent the bank")

	// The rate and the ceiling both doubled, so the fill time did not move.
	uassert.Equal(t, int64(2), rate(m.level, m.prestige).Amount)
	uassert.Equal(t, 2*CapPeriods, rate(m.level, m.prestige).Cap)
}

func TestUpgradeTooPoorPanics(cur realm, t *testing.T) {
	reset()
	alice := testutils.TestAddress("alice")
	start(alice, t0)
	uassert.PanicsContains(t, cur, "upgrade costs 10 ore, you have 0",
		func() { upgrade(alice, t0) })
}

func TestPrestigeIsLockedUntilLevelTen(cur realm, t *testing.T) {
	reset()
	alice := testutils.TestAddress("alice")
	start(alice, t0)
	uassert.PanicsContains(t, cur, "prestige unlocks at level 10",
		func() { prestige(alice, t0) })
}

func TestPrestigeResetsButKeepsLifetime(t *testing.T) {
	reset()
	alice := testutils.TestAddress("alice")
	start(alice, t0)
	m, _ := get(alice)

	// Hand the mine to level 10 rather than grinding it, then bank something
	// so the reset has ore to burn.
	m.level = PrestigeAt
	claim(alice, t0+50*Period)
	banked, lifetime := m.banked, m.lifetime
	uassert.True(t, banked > 0, "expected ore to burn")

	out := prestige(alice, t0+50*Period)
	uassert.True(t, strings.Contains(out, "Prestige 1"), "got: "+out)
	uassert.Equal(t, int64(1), m.prestige)
	uassert.Equal(t, int64(1), m.level)
	uassert.Equal(t, int64(0), m.banked, "prestige burns the bank")
	uassert.Equal(t, int64(0), m.pending)
	uassert.Equal(t, lifetime, m.lifetime, "lifetime survives the reset")

	// A level-1 prestige-1 mine digs what a level-2 mine does.
	uassert.Equal(t, int64(2), rate(m.level, m.prestige).Amount)
}

func TestReadHelpersAreSafeOnAStranger(t *testing.T) {
	reset()
	carol := testutils.TestAddress("carol")
	uassert.Equal(t, int64(0), Pending(carol))
	uassert.Equal(t, int64(0), Banked(carol))
	uassert.Equal(t, int64(0), FullAt(carol))
	lvl, pre := Level(carol)
	uassert.Equal(t, int64(0), lvl)
	uassert.Equal(t, int64(0), pre)
}

func TestSpan(t *testing.T) {
	cases := []struct {
		secs int64
		want string
	}{
		{0, "0s"},
		{-5, "0s"},
		{1, "1s"},
		{59, "59s"},
		{60, "1m"},
		{61, "1m 1s"},
		{3600, "1h"},
		{3661, "1h 1m"},
		{86400, "1d"},
		{90061, "1d 1h"},
		{7200, "2h"},
	}
	for _, tc := range cases {
		uassert.Equal(t, tc.want, span(tc.secs), "span("+tc.want+")")
	}
}

func TestRenderBoard(t *testing.T) {
	reset()
	uassert.True(t, strings.Contains(board(t0), "Nobody is digging yet"),
		"expected the empty placeholder")

	alice := testutils.TestAddress("alice")
	start(alice, t0)
	out := board(t0 + 30*Period)
	uassert.True(t, strings.Contains(out, "The Mine"), "expected the title")
	uassert.True(t, strings.Contains(out, "30"), "expected the live pending figure")
	uassert.True(t, strings.Contains(out, "to spill"), "expected the spill countdown")
}

func TestRenderCard(t *testing.T) {
	reset()
	alice := testutils.TestAddress("alice")
	start(alice, t0)

	out := card(alice, t0+30*Period)
	uassert.True(t, strings.Contains(out, "Level **1**"), "got: "+out)
	uassert.True(t, strings.Contains(out, "30 / 120"), "expected stock over cap")
	uassert.True(t, strings.Contains(out, "1h 30m"), "expected the spill countdown")
	uassert.True(t, strings.Contains(out, "10 short"), "expected the shortfall")
	uassert.True(t, strings.Contains(out, "9 to go"), "expected the prestige distance")

	full := card(alice, t0+999*Period)
	uassert.True(t, strings.Contains(full, "already full"), "expected the waste warning")

	bob := testutils.TestAddress("bob")
	uassert.True(t, strings.Contains(card(bob, t0), "No mine at"), "expected the stranger card")
}

// TestRenderIsLive is the property the whole design is for: the page changes
// with nothing but the passage of time, so gnoweb serves a live dashboard and
// no transaction was needed to move it.
func TestRenderIsLive(t *testing.T) {
	reset()
	alice := testutils.TestAddress("alice")
	start(alice, t0)

	early := board(t0 + 10*Period)
	later := board(t0 + 20*Period)
	uassert.NotEqual(t, early, later, "the board did not move with time")
	uassert.Equal(t, int64(0), Pending(testutils.TestAddress("nobody")),
		"and reading it wrote nothing")
}
