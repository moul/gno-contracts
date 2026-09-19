// Package logic is version 1 of the logic realm of the "state realm + swappable
// logic" upgrade pattern (pattern C of the exploration; see ../../README.md).
//
// Same shape as v0, different rule. The counter it reads and writes is the same
// one v0 was using: the upgrade changed the code without touching the data.
package logic

import (
	root "gno.land/r/moul/x/upgrade/store/root/v0"

	"gno.land/p/nt/ufmt/v0"
)

// Step is this version's business rule: the change that justified the upgrade.
const Step = 1000

// Inc applies this version's rule to the shared counter.
func Inc(cur realm) int {
	return root.Inc(cross(cur), Step)
}

// Get reads the shared counter, including everything v0 wrote.
func Get() int {
	return root.Get()
}

func Render(_ string) string {
	return ufmt.Sprintf("store/logic/v1: counter=%d step=%d\n", Get(), Step)
}
