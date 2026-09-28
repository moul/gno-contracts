// Package wrap is version 0 of the "wrapping versions" upgrade pattern
// (pattern A of the exploration; see ../README.md).
//
// Nothing here knows that a successor exists. v0 keeps its own counter and
// stays writable forever: callers pinned to this path keep working, and keep
// diverging from whatever the newer version reports.
package wrap

import "gno.land/p/nt/ufmt/v0"

var counter int

// Inc adds n to this version's own counter.
func Inc(cur realm, n int) {
	counter += n
}

// Get returns this version's counter. Non-crossing on purpose: a successor
// reads it without entering this realm as a writer.
func Get() int {
	return counter
}

func Render(_ string) string {
	return ufmt.Sprintf("wrap/v0: %d\n", counter)
}
