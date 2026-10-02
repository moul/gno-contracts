// PKGPATH: gno.land/r/test/main
//
// Renders the registry from ANOTHER realm, which is the case a unit test in
// the package cannot reach: there, CurrentRealm is the zones realm itself.
// Here Render is borrowed, CurrentRealm is gno.land/r/test/main, and every
// action link must still call the zones realm, not the one embedding it.
package main

import (
	"strings"

	zones "gno.land/r/moul/zones/v0"
)

func main() {
	page := zones.Render("") + zones.Render("zone/onyx")
	println(strings.Contains(page, "/r/moul/zones/v0$help&func=ProposeZone"))
	println(strings.Contains(page, "/r/moul/zones/v0$help&func=RegisterEndpoint"))
	println(strings.Contains(page, "/r/test/main$help"))
}

// Output:
// true
// true
// false
