// PKGPATH: gno.land/r/moul/x/plan9/main
package main

// Grafting another realm's tree into your namespace gives you reads and
// nothing else. ninep.File has no mutating method, so there is no route from a
// mount to a write against the realm that posted it.

import (
	"testing"

	"gno.land/p/nt/testutils/v0"

	synfs "gno.land/p/moul/x/plan9/synfs/v0"

	ns "gno.land/r/moul/x/plan9/ns/v0"
)

func main(cur realm) {
	t := synfs.New("probe", "sys", nil)
	t.Root().Add("value", func() string { return "read me" })
	ns.Post(cross(cur), "probe", t.Root())

	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("glenda")))
	println(ns.Exec(cross(cur), "bind /srv/probe /dev; cat /dev/value"))
	ns.Exec(cross(cur), "echo nope > /dev/value")
	println("unreachable")
}

// Error:
// echo: read-only file server
