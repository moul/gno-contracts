// Package logic is version 0 of the logic realm of the "state realm + swappable
// logic" upgrade pattern (pattern C of the exploration; see ../../README.md).
//
// It owns no state at all. Everything it writes lands in the root data realm,
// which is what makes replacing this realm cheap: there is nothing here to
// migrate.
package logic

import (
	root "gno.land/r/moul/x/upgrade/store/root/v0"

	"gno.land/p/nt/ufmt/v0"
)

// Step is this version's business rule: one call, one unit.
const Step = 1

// Inc applies this version's rule to the shared counter.
func Inc(cur realm) int {
	return root.Inc(cross(cur), Step)
}

// Get reads the shared counter. Same number every version sees.
func Get() int {
	return root.Get()
}

func Render(_ string) string {
	return ufmt.Sprintf("store/logic/v0: counter=%d step=%d\n", Get(), Step)
}
