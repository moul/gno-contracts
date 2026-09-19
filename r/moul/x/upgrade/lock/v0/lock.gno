// Package lock is version 0 of the "retire the predecessor" upgrade pattern
// (pattern B of the exploration; see ../README.md).
//
// Unlike pattern A, this version knows it can be superseded. Retire() freezes
// it and names its successor, and the freeze is one-way: once a successor has
// absorbed this version's total, re-opening it here would double-count.
package lock

import (
	"gno.land/p/nt/ownable/v0"
	"gno.land/p/nt/ufmt/v0"
)

const owner address = "g1manfred47kzduec920z88wfr64ylksmdcedlf5" // @moul

var (
	Ownable = ownable.NewWithAddress(owner)

	counter   int
	successor string // pkgpath that replaced this one; "" while this version is live
)

// Inc adds n. It aborts once a successor has been declared.
func Inc(cur realm, n int) {
	if successor != "" {
		panic("lock/v0 is retired, use " + successor)
	}
	counter += n
}

// Get returns this version's final (or current) total.
func Get() int {
	return counter
}

// Successor is the path callers should move to, or "" while this version is live.
func Successor() string {
	return successor
}

// Retire freezes this version and names its replacement. Owner-gated, one-way.
func Retire(cur realm, pkgPath string) {
	Ownable.AssertOwnedBy(cur.Previous().Address())
	if successor != "" {
		panic("lock/v0 is already retired, successor is " + successor)
	}
	if pkgPath == "" {
		panic("successor path must not be empty")
	}
	successor = pkgPath
}

func Render(_ string) string {
	if successor == "" {
		return ufmt.Sprintf("lock/v0: %d (live)\n", counter)
	}
	return ufmt.Sprintf("lock/v0: %d (retired, use %s)\n", counter, successor)
}
