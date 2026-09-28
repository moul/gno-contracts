// Package wrap is version 1 of the "wrapping versions" upgrade pattern
// (pattern A of the exploration; see ../README.md).
//
// v1 owns a counter of its own and ADDS v0's on read. Both versions stay live
// and independently writable, so the two paths report different totals and
// neither is authoritative. That is the pattern's defining trade-off: no
// migration, no downtime, no coordination — and no single answer either.
package wrap

import (
	v0 "gno.land/r/moul/x/upgrade/wrap/v0"

	"gno.land/p/nt/ufmt/v0"
)

var counter int

// Inc adds n to this version's own counter. It does NOT touch v0.
func Inc(cur realm, n int) {
	counter += n
}

// Get returns v0's counter plus this version's own. Reading across the version
// boundary is a plain non-crossing call: no realm is entered as a writer, so
// this stays queryable from vm/qeval and from Render.
func Get() int {
	return v0.Get() + counter
}

func Render(_ string) string {
	return ufmt.Sprintf("wrap/v1: %d (own %d + v0 %d)\n", Get(), counter, v0.Get())
}
