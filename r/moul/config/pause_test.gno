package config

import (
	"testing"

	"gno.land/p/moul/pausable/v0"
	"gno.land/p/nt/uassert/v0"
)

func TestPauseDefaultRunning(t *testing.T) {
	resetSettings()
	uassert.False(t, IsPausedFor(otherRealm))
	uassert.True(t, PauseFor(otherRealm).AllowsRead())
	uassert.True(t, PauseFor(otherRealm).AllowsWrite())
	AssertWritableFor(otherRealm)
	AssertReadableFor(otherRealm)
}

func TestPauseGlobal(cur realm, t *testing.T) {
	resetSettings()
	testing.SetRealm(testing.NewUserRealm(originAddr))
	Set(cross(cur), KeyPause, "readonly")

	// Reaches every realm.
	for _, path := range []string{otherRealm, "gno.land/r/moul/home", "gno.land/r/someone/else"} {
		uassert.True(t, IsPausedFor(path), path+" should be held back")
		uassert.True(t, PauseFor(path).AllowsRead(), path+" should still read")
		uassert.False(t, PauseFor(path).AllowsWrite(), path+" should refuse writes")
	}

	uassert.PanicsWithMessage(t, cur, "writes are paused", func() {
		AssertWritableFor(otherRealm)
	})
	AssertReadableFor(otherRealm)
}

func TestPauseScoped(cur realm, t *testing.T) {
	resetSettings()
	testing.SetRealm(testing.NewUserRealm(originAddr))
	Set(cross(cur), KeyFor(KeyPause, otherRealm), "paused: incident")

	uassert.True(t, IsPausedFor(otherRealm))
	uassert.False(t, PauseFor(otherRealm).AllowsRead())
	uassert.False(t, IsPausedFor("gno.land/r/moul/home"), "another realm is unaffected")

	uassert.PanicsWithMessage(t, cur, "paused: incident", func() {
		AssertReadableFor(otherRealm)
	})
}

// TestGlobalPauseCannotBeDefeated is the reason the two combine with
// Strictest. A per-realm entry left behind from last month must not re-open a
// realm during a global halt.
func TestGlobalPauseCannotBeDefeated(cur realm, t *testing.T) {
	resetSettings()
	testing.SetRealm(testing.NewUserRealm(originAddr))
	Set(cross(cur), KeyFor(KeyPause, otherRealm), "running")
	testing.SetRealm(testing.NewUserRealm(originAddr))
	Set(cross(cur), KeyPause, "paused: chain incident")

	uassert.False(t, PauseFor(otherRealm).AllowsRead(),
		"an explicit per-realm 'running' does not survive a global pause")
	uassert.Equal(t, "chain incident", PauseFor(otherRealm).Reason)

	// The other direction works: a per-realm pause under a running global.
	resetSettings()
	testing.SetRealm(testing.NewUserRealm(originAddr))
	Set(cross(cur), KeyFor(KeyPause, otherRealm), "paused: just this one")
	uassert.False(t, PauseFor(otherRealm).AllowsRead())
	uassert.True(t, PauseFor("gno.land/r/moul/home").AllowsRead())
}

// TestPauseValueValidatedOnWrite is the other half of failing closed. Because
// pausable.MustParse turns an unreadable value into Paused, an unvalidated
// typo here would take every realm offline at the next render; refusing the
// write turns that into a failed transaction the writer sees at once.
func TestPauseValueValidatedOnWrite(cur realm, t *testing.T) {
	resetSettings()

	for _, bad := range []string{"yes", "true", "1", "stop", "read-only"} {
		testing.SetRealm(testing.NewUserRealm(originAddr))
		uassert.AbortsContains(t, cur, "invalid pause value", func() {
			Set(cross(cur), KeyPause, bad)
		})
	}
	uassert.Equal(t, 0, Size(), "no bad value was stored")

	// The scoped key is validated too: the check is on the key's NAME, so it
	// cannot be sidestepped by scoping it.
	testing.SetRealm(testing.NewUserRealm(originAddr))
	uassert.AbortsContains(t, cur, "invalid pause value", func() {
		Set(cross(cur), KeyFor(KeyPause, otherRealm), "yes")
	})

	// And every value the reader understands is accepted.
	for _, good := range []string{"", "running", "readonly", "paused", "paused: why"} {
		testing.SetRealm(testing.NewUserRealm(originAddr))
		Set(cross(cur), KeyPause, good)
		uassert.Equal(t, good, Get(KeyPause))
	}

	// A setting that is not pause is not subject to the grammar.
	testing.SetRealm(testing.NewUserRealm(originAddr))
	Set(cross(cur), "some.key", "yes")
	uassert.Equal(t, "yes", Get("some.key"))
}

func TestPauseZeroArgFormsNameTheCaller(cur realm, t *testing.T) {
	resetSettings()
	testing.SetRealm(testing.NewUserRealm(originAddr))
	Set(cross(cur), KeyFor(KeyPause, otherRealm), "paused")

	testing.SetRealm(testing.NewCodeRealm(otherRealm))
	uassert.True(t, IsPaused())
	uassert.Equal(t, int(pausable.Paused), int(Pause().Level))

	testing.SetRealm(testing.NewCodeRealm("gno.land/r/moul/home"))
	uassert.False(t, IsPaused(), "another realm is unaffected")
	AssertWritable()
}
