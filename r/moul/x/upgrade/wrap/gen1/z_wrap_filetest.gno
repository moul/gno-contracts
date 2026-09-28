// PKGPATH: gno.land/r/moul/main
package main

import (
	v0 "gno.land/r/moul/x/upgrade/wrap/v0"
	v1 "gno.land/r/moul/x/upgrade/wrap/v1"
)

// Both versions stay writable, and writing one never moves the other.
func main(cur realm) {
	print(v0.Render(""))
	print(v1.Render(""))

	v0.Inc(cross(cur), 10)
	print(v0.Render(""))
	print(v1.Render(""))

	v1.Inc(cross(cur), 100)
	print(v0.Render(""))
	print(v1.Render(""))
}

// Output:
// wrap/v0: 0
// wrap/v1: 0 (own 0 + v0 0)
// wrap/v0: 10
// wrap/v1: 10 (own 0 + v0 10)
// wrap/v0: 10
// wrap/v1: 110 (own 100 + v0 10)
