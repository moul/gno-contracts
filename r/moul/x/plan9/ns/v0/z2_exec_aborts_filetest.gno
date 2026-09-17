// PKGPATH: gno.land/r/moul/x/plan9/main
package main

// A command line stops at the first error and the error leaves the realm as a
// panic, so a half-applied Exec reverts with its transaction instead of
// leaving a namespace nobody asked for.

import (
	"testing"

	"gno.land/p/nt/testutils/v0"

	ns "gno.land/r/moul/x/plan9/ns/v0"
)

func main(cur realm) {
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("glenda")))
	ns.Exec(cross(cur), "echo ok > /tmp/a; cat /absent; echo never > /tmp/b")
	println("unreachable")
}

// Error:
// cat: file does not exist
