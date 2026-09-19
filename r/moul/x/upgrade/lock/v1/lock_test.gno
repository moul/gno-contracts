package lock

import (
	"testing"

	v0 "gno.land/r/moul/x/upgrade/lock/v0"

	"gno.land/p/nt/uassert/v0"
)

// TestHandover walks the whole one-writer-at-a-time sequence in order: only v0
// writes, then the retirement flips it, then only v1 writes.
func TestHandover(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(v0.Ownable.Owner()))

	// Before the handover: v0 writes, v1 refuses.
	v0.Inc(cross(cur), 10)
	uassert.False(t, Live(), "v1 must not be live before the handover")
	uassert.AbortsContains(t, cur, "not live yet", func() {
		Inc(cross(cur), 1)
	})
	uassert.Equal(t, 10, Get(), "v1 already reports v0's running total")

	// The handover itself.
	v0.Retire(cross(cur), "gno.land/r/moul/x/upgrade/lock/v1")
	uassert.True(t, Live(), "v1 must be live once v0 names it")

	// After: v0 refuses, v1 writes, the total is single-valued.
	uassert.AbortsContains(t, cur, "is retired", func() {
		v0.Inc(cross(cur), 1)
	})
	Inc(cross(cur), 100)
	uassert.Equal(t, 110, Get(), "v1 folds v0's frozen total into its own")
	uassert.Equal(t, 10, v0.Get(), "v0's total is frozen where it stopped")

	// Retirement is one-way.
	uassert.AbortsContains(t, cur, "already retired", func() {
		v0.Retire(cross(cur), "gno.land/r/moul/x/upgrade/lock/v2")
	})

	uassert.Equal(t, "lock/v1: 110 (own 100 + retired v0 10)\n", Render(""))
	uassert.Equal(t, "lock/v0: 10 (retired, use gno.land/r/moul/x/upgrade/lock/v1)\n", v0.Render(""))
}
