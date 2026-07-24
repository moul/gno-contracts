package linktree

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils"
	"gno.land/p/nt/uassert"
)

func TestProfileLifecycle(cur realm, t *testing.T) {
	alice := testutils.TestAddress("alice")
	testing.SetRealm(testing.NewUserRealm(alice))

	cross(cur, SetBio)("gnome builder")
	cross(cur, AddLink)("Home", "https://alice.example")
	cross(cur, AddLink)("GitHub", "https://github.com/alice")

	out := Render("/" + alice.String())
	uassert.True(t, strings.Contains(out, "gnome builder"), "bio present")
	uassert.True(t, strings.Contains(out, "[Home](https://alice.example)"), "first link present")
	uassert.True(t, strings.Contains(out, "[GitHub](https://github.com/alice)"), "second link present")

	// Remove the first link; second must survive.
	cross(cur, RemoveLink)(0)
	out = Render("/" + alice.String())
	uassert.False(t, strings.Contains(out, "[Home]"), "removed link gone")
	uassert.True(t, strings.Contains(out, "[GitHub](https://github.com/alice)"), "kept link present")
}

func TestIndexAndOwnership(cur realm, t *testing.T) {
	alice := testutils.TestAddress("alice2")
	bob := testutils.TestAddress("bob2")

	testing.SetRealm(testing.NewUserRealm(alice))
	cross(cur, AddLink)("A", "https://a.example")

	testing.SetRealm(testing.NewUserRealm(bob))
	cross(cur, AddLink)("B", "https://b.example")

	// Root index lists both addresses.
	idx := Render("")
	uassert.True(t, strings.Contains(idx, alice.String()), "alice listed")
	uassert.True(t, strings.Contains(idx, bob.String()), "bob listed")

	// bob is current caller; his profile has only his link, not alice's.
	bobOut := Render("/" + bob.String())
	uassert.True(t, strings.Contains(bobOut, "[B](https://b.example)"), "bob has own link")
	uassert.False(t, strings.Contains(bobOut, "[A]"), "bob does not have alice's link")

	// Out-of-range removal on bob aborts.
	uassert.AbortsWithMessage(t, "index out of range", func() {
		cross(cur, RemoveLink)(99)
	})
}

func TestUnknownProfile(t *testing.T) {
	out := Render("/g1doesnotexist")
	uassert.True(t, strings.Contains(out, "No profile for this address"), "unknown profile message")
}
