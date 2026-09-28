// untrusted-render: live is the only stored string Render echoes, and SetLive
// validates it with assertPkgPath before storing it.
//
// Package root is the data realm of the "state realm + swappable logic" upgrade
// pattern (pattern C of the exploration; see ../../README.md).
//
// root holds the state and nothing else worth changing. It grants write access
// to exactly one logic realm at a time, identified by package path off the
// crossing frame rather than passed in as an argument, so a logic realm cannot
// claim to be a path it does not occupy. Upgrading is a single SetLive call:
// no migration, no downtime, and the data never moves.
package root

import (
	"strings"
	"gno.land/p/nt/ownable/v0"
	"gno.land/p/nt/ufmt/v0"
)

const owner address = "g1manfred47kzduec920z88wfr64ylksmdcedlf5" // @moul

var (
	Ownable = ownable.NewWithAddress(owner)

	counter int
	live    = "gno.land/r/moul/x/upgrade/store/logic/v0"
)

// Inc adds n to the stored counter. Only the live logic realm may call it.
func Inc(cur realm, n int) int {
	assertCallerIsLive(cur)
	counter += n
	return counter
}

// Get is open to everyone: the data is public, only writes are gated.
func Get() int {
	return counter
}

// Live is the package path currently allowed to write.
func Live() string {
	return live
}

// SetLive hands write access to another logic realm. This is the upgrade.
func SetLive(cur realm, pkgPath string) {
	Ownable.AssertOwnedBy(cur.Previous().Address())
	assertPkgPath(pkgPath)
	live = pkgPath
}

func assertCallerIsLive(cur realm) {
	caller := cur.Previous().PkgPath()
	if caller != live {
		panic("unauthorized: " + caller + " is not the live logic realm (" + live + ")")
	}
}

func Render(_ string) string {
	return ufmt.Sprintf("store/root/v0: %d (live logic: %s)\n", counter, live)
}

// assertPkgPath rejects anything that is not a gno.land realm path.
//
// It exists for Render, not for correctness of the upgrade: the stored path is
// echoed into markdown, so validating it at write time is what lets Render
// print it raw. ui.Inline would escape the dots in "gno.land" and turn the one
// string a reader needs to copy into "gno\.land".
func assertPkgPath(p string) {
	if !strings.HasPrefix(p, "gno.land/r/") {
		panic("not a realm path: " + p)
	}
	for _, c := range p {
		ok := c == '/' || c == '.' || c == '_' || c == '-' ||
			(c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
		if !ok {
			panic("illegal character in realm path")
		}
	}
}
