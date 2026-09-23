package vesting

import (
	"strings"
	"testing"

	"chain/runtime"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/nt/testutils/v0"
)

const (
	mainnetStart int64 = 1789225200
	mainnetEnd   int64 = 1852383600
	moul               = address("g1manfred47kzduec920z88wfr64ylksmdcedlf5")
)

// TestSeededSurvivesInit is the property the seed exists for: this realm is
// private = true, so a redeploy re-runs init() and wipes everything else. The
// one schedule the page is about has to come back without a transaction.
func TestSeededSurvivesInit(t *testing.T) {
	o, s, e, delayed, ok := ScheduleOf(moul)
	uassert.True(t, ok, "moul's schedule is missing after init")
	uassert.Equal(t, int64(106560000000), o)
	uassert.Equal(t, mainnetStart, s)
	uassert.Equal(t, mainnetEnd, e)
	uassert.False(t, delayed)
}

// TestDeclareWritesOnlyYourOwnRow is the entire trust model. A caller cannot
// name an address, so it cannot describe one but its own.
func TestDeclareWritesOnlyYourOwnRow(cur realm, t *testing.T) {
	alice := testutils.TestAddress("alice")
	bob := testutils.TestAddress("bob")

	testing.SetRealm(testing.NewUserRealm(alice))
	Declare(cross(cur), 500, 100, 200, false)

	o, s, e, delayed, ok := ScheduleOf(alice)
	uassert.True(t, ok)
	uassert.Equal(t, int64(500), o)
	uassert.Equal(t, int64(100), s)
	uassert.Equal(t, int64(200), e)
	uassert.False(t, delayed)

	// Nothing alice did touched bob.
	_, _, _, _, ok = ScheduleOf(bob)
	uassert.False(t, ok, "declaring for alice wrote a row for bob")
}

func TestDeclareReplacesAndForgetRemoves(cur realm, t *testing.T) {
	carol := testutils.TestAddress("carol")

	testing.SetRealm(testing.NewUserRealm(carol))
	Declare(cross(cur), 500, 100, 200, false)
	testing.SetRealm(testing.NewUserRealm(carol))
	Declare(cross(cur), 900, 10, 20, true)

	o, s, e, delayed, ok := ScheduleOf(carol)
	uassert.True(t, ok)
	uassert.Equal(t, int64(900), o)
	uassert.Equal(t, int64(10), s)
	uassert.Equal(t, int64(20), e)
	uassert.True(t, delayed, "the delayed flag did not survive")

	testing.SetRealm(testing.NewUserRealm(carol))
	Forget(cross(cur))
	_, _, _, _, ok = ScheduleOf(carol)
	uassert.False(t, ok, "Forget left the row behind")
}

func TestForgetWithoutADeclarationAborts(cur realm, t *testing.T) {
	dave := testutils.TestAddress("dave")
	testing.SetRealm(testing.NewUserRealm(dave))
	uassert.AbortsContains(t, cur, "nothing declared", func() { Forget(cross(cur)) })
}

// TestSeededRowIsNotWritable: the seeds are source, so a signer who happens to
// hold a seeded address still cannot rewrite it from a transaction. Otherwise
// a redeploy would silently revert whatever they set.
func TestSeededRowIsNotWritable(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(moul))
	uassert.AbortsContains(t, cur, "seeded in the source", func() {
		Declare(cross(cur), 1, 2, 3, false)
	})
	testing.SetRealm(testing.NewUserRealm(moul))
	uassert.AbortsContains(t, cur, "seeded in the source", func() { Forget(cross(cur)) })
}

func TestDeclareRejectsAnImpossibleSchedule(cur realm, t *testing.T) {
	erin := testutils.TestAddress("erin")
	testing.SetRealm(testing.NewUserRealm(erin))
	uassert.AbortsContains(t, cur, "start time must be before end time", func() {
		Declare(cross(cur), 100, 200, 100, false)
	})
	testing.SetRealm(testing.NewUserRealm(erin))
	uassert.AbortsContains(t, cur, "cannot be negative", func() {
		Declare(cross(cur), -1, 0, 100, false)
	})
}

// TestDeclareZeroMeansNoSchedule lets an address say "nothing of mine is
// locked", which is a real and useful claim.
func TestDeclareZeroMeansNoSchedule(cur realm, t *testing.T) {
	frank := testutils.TestAddress("frank")
	testing.SetRealm(testing.NewUserRealm(frank))
	Declare(cross(cur), 0, 0, 0, false)

	o, _, _, _, ok := ScheduleOf(frank)
	uassert.True(t, ok)
	uassert.Equal(t, int64(0), o)

	spend, known := SpendableOf(frank)
	uassert.True(t, known)
	uassert.Equal(t, balanceOf(frank), spend)
}

// TestUnknownAddressReportsItsBalanceAndSaysSo: the balance is real, the
// spendable figure is not, and the caller is told which is which.
func TestUnknownAddressReportsItsBalanceAndSaysSo(t *testing.T) {
	stranger := testutils.TestAddress("stranger")

	spend, ok := SpendableOf(stranger)
	uassert.False(t, ok, "an unknown address must not claim a known schedule")
	uassert.Equal(t, balanceOf(stranger), spend)

	locked, ok := LockedOf(stranger)
	uassert.False(t, ok)
	uassert.Equal(t, int64(0), locked)
}

func TestCountTracksTheRegistry(cur realm, t *testing.T) {
	before := Count()
	grace := testutils.TestAddress("grace")
	testing.SetRealm(testing.NewUserRealm(grace))
	Declare(cross(cur), 10, 1, 2, false)
	uassert.Equal(t, before+1, Count())
	testing.SetRealm(testing.NewUserRealm(grace))
	Forget(cross(cur))
	uassert.Equal(t, before, Count())
}

// TestLockedIsCappedByTheBalance: an account that spent while its coins were
// free can owe the schedule more than it now holds. The honest answer is that
// nothing moves, never a negative spendable.
func TestLockedIsCappedByTheBalance(cur realm, t *testing.T) {
	poor := testutils.TestAddress("poor")
	testing.SetRealm(testing.NewUserRealm(poor))
	Declare(cross(cur), 1000000000000, mainnetStart, mainnetEnd, false)

	locked, ok := LockedOf(poor)
	uassert.True(t, ok)
	uassert.Equal(t, balanceOf(poor), locked, "locked must not exceed the balance")

	spend, _ := SpendableOf(poor)
	uassert.Equal(t, int64(0), spend)
	uassert.True(t, spend >= 0, "spendable went negative")
}

func TestIsAddr(t *testing.T) {
	uassert.True(t, isAddr("g1manfred47kzduec920z88wfr64ylksmdcedlf5"))
	uassert.False(t, isAddr(""))
	uassert.False(t, isAddr("g1manfred"))
	uassert.False(t, isAddr("x1manfred47kzduec920z88wfr64ylksmdcedlf5"))
	uassert.False(t, isAddr("g1MANFRED47kzduec920z88wfr64ylksmdcedlf5"))
	uassert.False(t, isAddr("g1manfred47kzduec920z88wfr64ylksmdcedlf5x"))
}

func TestGnotFormatting(t *testing.T) {
	uassert.Equal(t, "0.000000 GNOT", gnot(0))
	uassert.Equal(t, "0.000001 GNOT", gnot(1))
	uassert.Equal(t, "1.000000 GNOT", gnot(1000000))
	uassert.Equal(t, "106560.000000 GNOT", gnot(106560000000))
	uassert.Equal(t, "1.234567 GNOT", gnot(1234567))
	uassert.Equal(t, "-1.500000 GNOT", gnot(-1500000))
}

func TestPermilleFormatting(t *testing.T) {
	uassert.Equal(t, "0.0%", permille(0))
	uassert.Equal(t, "5.0%", permille(50))
	uassert.Equal(t, "49.9%", permille(499))
	uassert.Equal(t, "100.0%", permille(1000))
}

func TestDurationFormatting(t *testing.T) {
	uassert.Equal(t, "complete", duration(0))
	uassert.Equal(t, "complete", duration(-1))
	uassert.Equal(t, "0h", duration(60))
	uassert.Equal(t, "1h", duration(3600))
	uassert.Equal(t, "1d 0h", duration(86400))
	uassert.Equal(t, "2d 3h", duration(2*86400+3*3600))
}

// TestCivilDates pins the date arithmetic against dates that are known exactly,
// including the two ends of the real mainnet term and a leap day.
func TestCivilDates(t *testing.T) {
	uassert.Equal(t, "1970-01-01", tstamp(0))
	uassert.Equal(t, "2000-02-29", tstamp(951782400))
	uassert.Equal(t, "2026-09-12", tstamp(mainnetStart))
	uassert.Equal(t, "2028-09-12", tstamp(mainnetEnd))
}

// TestRenderShapes walks the three routes the page serves and checks each one
// names its source, which is the promise the whole realm makes.
func TestRenderShapes(t *testing.T) {
	index := Render("")
	uassert.True(t, strings.Contains(index, "# Vesting"), "index has no title")
	uassert.True(t, strings.Contains(index, "no realm can read one"),
		"index does not say the schedule is supplied")

	seeded := Render(moul.String())
	uassert.True(t, strings.Contains(seeded, "seeded in this realm's source"),
		"a seeded row does not say where it came from")
	uassert.True(t, strings.Contains(seeded, "spendable now"))

	query := Render(moul.String() + "?o=1000000&s=100&e=200")
	uassert.True(t, strings.Contains(query, "supplied in the URL by you"),
		"a query schedule does not say it was supplied")
	uassert.True(t, strings.Contains(query, "Nothing was stored."))

	unknown := Render(testutils.TestAddress("nobody").String())
	uassert.True(t, strings.Contains(unknown, "No schedule on file"))
	uassert.True(t, strings.Contains(unknown, "gnokey query auth/accounts/"),
		"the unknown page does not say how to find the schedule")

	bad := Render("not-an-address")
	uassert.True(t, strings.Contains(bad, "is not a gno.land address"))
}

// TestRenderEscapesWhatTheCallerTyped: the path is attacker-controlled and a
// live realm can never be patched, so the escaping is checked before deploy.
func TestRenderEscapesWhatTheCallerTyped(t *testing.T) {
	out := Render("[x](/r/evil)")
	uassert.False(t, strings.Contains(out, "[x](/r/evil)"),
		"a markdown link typed into the path reached the page unescaped")
}

// TestRenderQueryRejectsGarbage keeps a typo readable instead of rendering a
// schedule of zeroes as though it were real.
func TestRenderQueryRejectsGarbage(t *testing.T) {
	out := Render(moul.String() + "?o=abc")
	uassert.True(t, strings.Contains(out, "is not a number"))

	out = Render(moul.String() + "?o=100&s=200&e=100")
	uassert.True(t, strings.Contains(out, "not a valid schedule"))
}

// TestChainHeightIsReadable guards the one call that would make Declare
// non-deterministic if it were wrong.
func TestChainHeightIsReadable(t *testing.T) {
	uassert.Equal(t, runtime.ChainHeight(), chainHeight())
}
