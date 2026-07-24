package linktree

import (
	"strings"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

func TestProfileLifecycle(cur realm, t *testing.T) {
	alice := testutils.TestAddress("alice")
	testing.SetRealm(testing.NewUserRealm(alice))

	SetBio(cross(cur), "gnome builder")
	AddLink(cross(cur), "Home", "https://alice.example")
	AddLink(cross(cur), "GitHub", "https://github.com/alice")

	out := Render("/" + alice.String())
	uassert.True(t, strings.Contains(out, "gnome builder"), "bio present")
	uassert.True(t, strings.Contains(out, "[Home](https://alice.example)"), "first link present")
	uassert.True(t, strings.Contains(out, "[GitHub](https://github.com/alice)"), "second link present")

	// Remove the first link; second must survive.
	RemoveLink(cross(cur), 0)
	out = Render("/" + alice.String())
	uassert.False(t, strings.Contains(out, "[Home]"), "removed link gone")
	uassert.True(t, strings.Contains(out, "[GitHub](https://github.com/alice)"), "kept link present")
}

func TestIndexAndOwnership(cur realm, t *testing.T) {
	alice := testutils.TestAddress("alice2")
	bob := testutils.TestAddress("bob2")

	testing.SetRealm(testing.NewUserRealm(alice))
	AddLink(cross(cur), "A", "https://a.example")

	testing.SetRealm(testing.NewUserRealm(bob))
	AddLink(cross(cur), "B", "https://b.example")

	// Root index lists both addresses.
	idx := Render("")
	uassert.True(t, strings.Contains(idx, alice.String()), "alice listed")
	uassert.True(t, strings.Contains(idx, bob.String()), "bob listed")

	// bob is current caller; his profile has only his link, not alice's.
	bobOut := Render("/" + bob.String())
	uassert.True(t, strings.Contains(bobOut, "[B](https://b.example)"), "bob has own link")
	uassert.False(t, strings.Contains(bobOut, "[A]"), "bob does not have alice's link")

	// Out-of-range removal on bob aborts.
	uassert.AbortsWithMessage(t, cur, "index out of range", func() {
		RemoveLink(cross(cur), 99)
	})
}

func TestUnknownProfile(t *testing.T) {
	out := Render("/g1doesnotexist")
	uassert.True(t, strings.Contains(out, "No profile for this address"), "unknown profile message")
}
