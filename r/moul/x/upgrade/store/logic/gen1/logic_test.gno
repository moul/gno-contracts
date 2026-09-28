package logic

import (
	"testing"

	logicv0 "gno.land/r/moul/x/upgrade/store/logic/v0"
	root "gno.land/r/moul/x/upgrade/store/root/v0"

	"gno.land/p/nt/uassert/v0"
)

// TestSwapLogic shows the upgrade: the counter survives it untouched, and only
// the realm root currently points at may write.
func TestSwapLogic(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(root.Ownable.Owner()))

	// v0 is live out of the box.
	uassert.Equal(t, 1, logicv0.Inc(cross(cur)))
	uassert.Equal(t, 2, logicv0.Inc(cross(cur)))
	uassert.AbortsContains(t, cur, "is not the live logic realm", func() {
		Inc(cross(cur))
	})

	// The upgrade: one call, no migration.
	root.SetLive(cross(cur), "gno.land/r/moul/x/upgrade/store/logic/v1")

	// v1 writes on top of the data v0 left; v0 is locked out by the same gate.
	uassert.Equal(t, 1002, Inc(cross(cur)), "v1 adds its own step to v0's data")
	uassert.AbortsContains(t, cur, "is not the live logic realm", func() {
		logicv0.Inc(cross(cur))
	})

	// Reads stay open to every version, live or not.
	uassert.Equal(t, 1002, logicv0.Get(), "a retired version still reads the truth")
	uassert.Equal(t, "store/logic/v1: counter=1002 step=1000\n", Render(""))
	uassert.Equal(t, "store/logic/v0: counter=1002 step=1\n", logicv0.Render(""))
}
