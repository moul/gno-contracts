// PKGPATH: gno.land/r/moul/x/plan9/main
package main

// A /srv name belongs to the realm that posted it. A second realm cannot take
// it over, which is the whole of v0's squatting story: first come, first
// served, and then locked.

import (
	"testing"

	synfs "gno.land/p/moul/x/plan9/synfs/v0"

	ns "gno.land/r/moul/x/plan9/ns/v0"
)

func tree(value string) *synfs.Tree {
	t := synfs.New("probe", "sys", nil)
	t.Root().Add("value", func() string { return value })
	return t
}

func main(cur realm) {
	ns.Post(cross(cur), "probe", tree("first").Root())
	println("posted:", ns.Services())

	testing.SetRealm(testing.NewCodeRealm("gno.land/r/other/thing/v0"))
	ns.Post(cross(cur), "probe", tree("second").Root())
	println("unreachable")
}

// Error:
// post: probe is already posted by gno.land/r/moul/x/plan9/main
