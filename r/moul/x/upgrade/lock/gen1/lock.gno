// Package lock is version 1 of the "retire the predecessor" upgrade pattern
// (pattern B of the exploration; see ../README.md).
//
// v1 refuses every write until v0 has been retired. That is the whole point:
// at most one version is writable at any height, so v1 can safely fold v0's
// frozen total into its own and report a single authoritative number — the
// thing pattern A cannot do.
package lock

import (
	v0 "gno.land/r/moul/x/upgrade/lock/v0"

	"gno.land/p/nt/ufmt/v0"
)

// Predecessor is the version this one supersedes.
const Predecessor = "gno.land/r/moul/x/upgrade/lock/v0"

var counter int

// Inc adds n once the predecessor is frozen.
func Inc(cur realm, n int) {
	assertPredecessorRetired()
	counter += n
}

// Get returns the predecessor's frozen total plus this version's own.
func Get() int {
	return v0.Get() + counter
}

// Live reports whether the handover has happened.
func Live() bool {
	return v0.Successor() == "gno.land/r/moul/x/upgrade/lock/v1"
}

func assertPredecessorRetired() {
	if !Live() {
		panic("lock/v1 is not live yet, " + Predecessor + " must be retired onto it first")
	}
}

func Render(_ string) string {
	if !Live() {
		return ufmt.Sprintf("lock/v1: waiting for %s to retire\n", Predecessor)
	}
	return ufmt.Sprintf("lock/v1: %d (own %d + retired v0 %d)\n", Get(), counter, v0.Get())
}
