package config

import "gno.land/p/moul/pausable/v0"

// The pause switch: one setting that stops every realm reading this one, and
// one per realm that stops just that one.
//
//	Set pause              "paused: incident, back in an hour"
//	Set pause@r/moul/gns   "readonly"
//	Unset pause            # running again
//
// A realm guards its writes and leaves its reads alone, which is what makes
// "readonly" the level worth having: the page keeps rendering and explains
// itself through TopBlock, and nothing new lands.
//
//	func Post(cur realm, body string) {
//		config.AssertWritable()
//		…
//	}
//
// The levels, the fail-closed parse and the stricter-of-two rule all live in
// gno.land/p/moul/pausable; this file is only the wiring to storage.
const KeyPause = "pause"

// Pause returns the pause state of the realm calling in: the stricter of the
// global setting and that realm's own.
func Pause() pausable.State { return PauseFor(caller()) }

// PauseFor is Pause for a named realm.
//
// A stale per-realm entry can never re-open a realm during a global pause,
// because the two combine with pausable.Strictest rather than one overriding
// the other. The cost is that exempting one realm from a global pause is not
// expressible: clear the global and set the others.
func PauseFor(pkgPath string) pausable.State {
	global, scoped := scopedPair(KeyPause, pkgPath)
	return pausable.Strictest(pausable.MustParse(global), pausable.MustParse(scoped))
}

// IsPaused reports whether the realm calling in is held back at all, ReadOnly
// as well as fully paused.
func IsPaused() bool { return Pause().IsPaused() }

// IsPausedFor is IsPaused for a named realm.
func IsPausedFor(pkgPath string) bool { return PauseFor(pkgPath).IsPaused() }

// AssertWritable aborts unless the realm calling in may still change state.
// This is the one line a mutating function needs.
func AssertWritable() { Pause().AssertWritable() }

// AssertWritableFor is AssertWritable for a named realm, for a crossing
// function that cannot be read off the stack.
func AssertWritableFor(pkgPath string) { PauseFor(pkgPath).AssertWritable() }

// AssertReadable aborts unless the realm calling in may still be read.
//
// Most realms should NOT put this in Render. A page that aborts tells a reader
// nothing; TopBlock tells them what happened and when to come back. Reach for
// this only where serving stale data is itself the harm.
func AssertReadable() { Pause().AssertReadable() }

// AssertReadableFor is AssertReadable for a named realm.
func AssertReadableFor(pkgPath string) { PauseFor(pkgPath).AssertReadable() }
